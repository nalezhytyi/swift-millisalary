import AppKit
import MillisalaryCore
import Observation

/// The menu bar item (tray.ts in the Electron app): the icon with today's
/// earnings next to it in monospaced digits, refreshed every second, and a
/// menu of the period amounts. An NSStatusItem rather than SwiftUI's
/// MenuBarExtra, for control over the title's font and so the open menu
/// can be updated in place
final class StatusItemController: NSObject {
    private let store: SettingsStore
    private let open: (Pane?) -> Void
    private let model = EarningsModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    private var amountItems: [NSMenuItem] = []
    private var content: MenuBarContent?

    /// `open` shows the main window, on a pane when one is given
    init(store: SettingsStore, open: @escaping (Pane?) -> Void) {
        self.store = store
        self.open = open
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(resource: .menuBarIcon)
            button.imagePosition = .imageLeading
            button.toolTip = "Millisalary"
            button.font = .monospacedDigitSystemFont(
                ofSize: button.font?.pointSize ?? NSFont.systemFontSize,
                weight: .regular
            )
        }
        menu.autoenablesItems = false
        statusItem.menu = menu

        refresh()
        observeSettings()

        // In the common modes the timer keeps firing while the menu is
        // open, so the amounts in it stay live
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
    }

    private func observeSettings() {
        withObservationTracking {
            _ = store.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeSettings()
            }
        }
    }

    private func refresh() {
        let settings = store.settings
        if statusItem.isVisible != settings.showInMenuBar {
            statusItem.isVisible = settings.showInMenuBar
        }

        let next = MenuBarContent(
            settings: settings,
            earnings: settings.monthlySalary > 0 ? settings.earnings(at: Clock.now, model: model) : nil,
            currency: settings.displayCurrency
        )
        guard next != content else { return }

        if next.title != content?.title {
            statusItem.button?.title = next.title
            #if DEBUG
            writeDebugSnapshot()
            #endif
        }
        if next.rows.count != amountItems.count || content == nil {
            rebuildMenu(rows: next.rows)
        } else {
            for (item, row) in zip(amountItems, next.rows) where item.title != row {
                item.title = row
            }
        }
        content = next
    }

    private func rebuildMenu(rows: [String]) {
        menu.removeAllItems()

        amountItems = rows.map { item($0, #selector(openBreakdown)) }
        amountItems.forEach(menu.addItem)
        if !rows.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(item("Open Millisalary", #selector(openWindow)))
        menu.addItem(item("Settings…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Millisalary",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openWindow() { open(nil) }
    @objc private func openSettings() { open(.settings) }
    @objc private func openBreakdown() { open(.breakdown) }

    #if DEBUG
    /// With the launch argument `-debugStatusItemSnapshot <path>`, each new
    /// title is also drawn into a PNG at that path. The menu bar can't be
    /// read otherwise without Accessibility or Screen Recording permission,
    /// and macOS hides an item that doesn't fit next to the notch
    private func writeDebugSnapshot() {
        guard let path = UserDefaults.standard.string(forKey: "debugStatusItemSnapshot") else { return }

        // After the status bar has resized the button for the new title.
        // The title is drawn partly below the button's bounds, so take
        // some room around them
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem.button else { return }
            let rect = button.bounds.insetBy(dx: -4, dy: -8)
            guard let bitmap = button.bitmapImageRepForCachingDisplay(in: rect) else { return }
            button.cacheDisplay(in: rect, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: path))
        }
    }
    #endif
}
