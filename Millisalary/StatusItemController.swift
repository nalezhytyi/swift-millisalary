import AppKit
import MillisalaryCore
import Observation

/// The menu bar item (tray.ts in the Electron app): a ring of today's working
/// hours, filled as the day goes, with the earnings next to it in monospaced
/// digits, refreshed every second, and a menu of the period amounts. An NSStatusItem rather than SwiftUI's
/// MenuBarExtra, for control over the title's font and so the open menu
/// can be updated in place
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: SettingsStore
    private let rates: ExchangeRateStore
    private let open: (Pane?) -> Void
    private let openSettings: () -> Void
    private let checkForUpdates: () -> Void
    private let menuOpened: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    private var amountItems: [NSMenuItem] = []
    private var content: MenuBarContent?
    private var ring: RingIcon?

    /// `open` shows the main window, on a pane when one is given
    init(
        store: SettingsStore,
        rates: ExchangeRateStore,
        open: @escaping (Pane?) -> Void,
        openSettings: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void,
        menuOpened: @escaping () -> Void
    ) {
        self.store = store
        self.rates = rates
        self.open = open
        self.openSettings = openSettings
        self.checkForUpdates = checkForUpdates
        self.menuOpened = menuOpened
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.toolTip = "Millisalary"
            button.font = .monospacedDigitSystemFont(
                ofSize: button.font?.pointSize ?? NSFont.systemFontSize,
                weight: .regular
            )
        }
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        // At once when the settings or the rate change, and every second;
        // the timer keeps firing while the menu is open, so the amounts in
        // it stay live
        followChanges { [weak self] in self?.refresh() }
        Timer.repeating(every: 1, tolerance: 0.1) { [weak self] in self?.refresh() }
    }

    private func refresh() {
        let settings = store.settings
        if statusItem.isVisible != settings.showInMenuBar {
            statusItem.isVisible = settings.showInMenuBar
        }

        let display = settings.amountDisplay(rates)
        let now = Clock.now
        let earnings = settings.monthlySalary > 0 ? settings.earnings(at: now, display) : nil

        // Before the amounts: the ring turns over at midnight even when the
        // title stays the same (This Month's amount, say)
        let nextRing = RingIcon(settings, earnings, at: now)
        if nextRing != ring {
            statusItem.button?.image = nextRing.image
            ring = nextRing
            #if DEBUG
            writeDebugSnapshot()
            #endif
        }

        let next = MenuBarContent(settings: settings, earnings: earnings, currency: display.currency)
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
        menu.addItem(item(String(localized: "Open Millisalary"), #selector(openWindow)))
        menu.addItem(item(String(localized: "Settings…"), #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Check for Updates…"), #selector(checkUpdates)))
        menu.addItem(NSMenuItem(
            title: String(localized: "Quit Millisalary"),
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
    @objc private func showSettings() { openSettings() }
    @objc private func openBreakdown() { open(.breakdown) }
    @objc private func checkUpdates() { checkForUpdates() }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpened()
    }

    #if DEBUG
    /// With the launch argument `-debugStatusItemSnapshot <path>`, each new
    /// title or ring is also drawn into a PNG at that path. The menu bar can't be
    /// read otherwise without Accessibility or Screen Recording permission,
    /// and macOS hides an item that doesn't fit next to the notch
    private func writeDebugSnapshot() {
        guard let path = UserDefaults.standard.string(forKey: "debugStatusItemSnapshot") else { return }

        // After the status bar has resized the button and laid out its
        // image and title, which the next turn of the run loop was too soon
        // for when both changed at once. The title is drawn partly below
        // the button's bounds, so take some room around them
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
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

/// The menu bar's icon: today's working hours cut into segments as on the
/// Today dial (`DialScale`), filled with the day's earnings, the rest faint.
/// Always today, whichever amount the title shows: a month's twenty-odd
/// segments wouldn't read at 16 pt. A template image, so macOS tints it for
/// the menu bar, a faint segment staying faint
private struct RingIcon: Equatable {
    let units: Double
    let fillStart: Double
    /// The fill as a fraction of the ring, in steps of 1/150, about half a
    /// pixel of the ring on a Retina screen: the image is drawn again every
    /// few minutes of a workday rather than every second
    let fraction: Double

    init(_ settings: MillisalaryCore.Settings, _ earnings: EarningsSnapshot?, at now: Date) {
        let model = EarningsModel()
        let scale = DialScale(.day, WorkdayState(settings, at: now, model: model), settings, at: now, model: model)
        let progress = earnings.map { $0.day.total > 0 ? min(1, max(0, $0.day.earned / $0.day.total)) : 0 } ?? 0
        units = scale.units
        fillStart = scale.fillStart
        fraction = ((scale.fillStart + progress * scale.unitsPerTotal) / scale.units * 150).rounded() / 150
    }

    var image: NSImage {
        // A ring of radius 6 in 16 pt, stroked with butt caps: round ones
        // would close the gaps at this size
        let track = DialSegments(units: units, fraction: 1, lineWidth: 1.8, gap: min(12, 360 / units * 0.3))
        var fill = track
        fill.from = fillStart
        fill.fraction = fraction
        let rect = CGRect(x: 2, y: 2, width: 12, height: 12)
        let paths = (track: track.path(in: rect).cgPath, fill: fill.path(in: rect).cgPath)

        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setLineWidth(1.8)
            context.setLineCap(.butt)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
            context.addPath(paths.track)
            context.strokePath()
            context.setStrokeColor(NSColor.black.cgColor)
            context.addPath(paths.fill)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
