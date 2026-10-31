import AppKit
import MillisalaryCore
import Observation

/// The menu bar item (tray.ts in the Electron app): the icon with today's
/// earnings next to it in monospaced digits, refreshed every second, and a
/// menu of the period amounts. An NSStatusItem rather than SwiftUI's
/// MenuBarExtra, for control over the title's font and so the open menu
/// can be updated in place
final class StatusItemController {
    private let store: SettingsStore
    private let model = EarningsModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var amountItems: [NSMenuItem] = []
    private var content: MenuBarContent?

    init(store: SettingsStore) {
        self.store = store

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
        // Until the exchange rate is ported, amounts stay in the salary's
        // own currency
        let earnings = settings.monthlySalary > 0
            ? model.earnings(at: Clock.now, settings.earningsSettings(exchangeRate: 1))
            : nil
        let next = MenuBarContent(
            settings: settings,
            earnings: earnings,
            currency: settings.monthlySalaryCurrency
        )
        guard next != content else { return }

        if next.title != content?.title {
            statusItem.button?.title = next.title
            #if DEBUG
            writeDebugSnapshot()
            #endif
        }
        if next.rows.count != amountItems.count {
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

        if rows.isEmpty {
            let hint = NSMenuItem(title: "No salary set", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        amountItems = rows.map { NSMenuItem(title: $0, action: nil, keyEquivalent: "") }
        amountItems.forEach(menu.addItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Millisalary",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }

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
