import AppKit
import MillisalaryCore
import Observation
import SwiftUI

/// Owns the app's parts and is what the menus, the menu bar item and the
/// Dock go through (showSection and friends in the Electron app's main
/// process)
final class AppController {
    static let mainWindowID = "main"

    let store = SettingsStore()
    let navigation = Navigation()
    let ticker = Ticker()
    let rates = ExchangeRateStore()
    private(set) lazy var notifications = NotificationController(store: store, rates: rates) { [weak self] in
        self?.show()
    }
    private(set) lazy var loginItem = LoginItemController(store: store)
    private var statusItem: StatusItemController?

    /// SwiftUI's way to open the main window (a `Window` scene), which the
    /// app menu's commands hand over: AppKit code like the menu bar item
    /// can't get it from a view's environment
    var openWindow: OpenWindowAction?

    /// Before the first window: whether it should stay closed (started at
    /// login: the menu bar item only), and the notification delegate, which
    /// UserNotifications wants set before launch finishes
    func prepareLaunch(launchEvent: NSAppleEventDescriptor?) {
        _ = notifications
        if LoginItemController.wasLaunchedAtLogin(launchEvent: launchEvent, settingOn: store.settings.launchAtLogin) {
            navigation.hideOnLaunch = true
        }
    }

    func start() {
        // One window, no tabs (and no tab items in the View and Window menus)
        NSWindow.allowsAutomaticWindowTabbing = false
        ElectronSettingsImport.runIfNeeded(into: store, rates: rates)
        followRatePair()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rates.refresh() }
        }
        statusItem = StatusItemController(store: store, rates: rates) { [weak self] pane in
            self?.show(pane)
        }
        followTheme()
        loginItem.start()
        notifications.start()
        #if DEBUG
        if let pane = Self.debugLaunchPane {
            navigation.pane = pane
        }
        DebugDump.scheduleIfAsked(statusMenu: statusItem?.menu)
        #endif
    }

    /// Opens the main window, or brings it to the front, on `pane` when one
    /// is given
    func show(_ pane: Pane? = nil) {
        if let pane {
            navigation.pane = pane
        }
        openWindow?(id: Self.mainWindowID)
        NSApp.activate()
    }

    /// Selects a period and shows its dial (⌘1-⌘5)
    func showPeriod(_ period: Period) {
        store.update { $0.selectedPeriod = period }
        show(.earnings)
    }

    /// The exchange rate follows the currencies in the settings
    private func followRatePair() {
        withObservationTracking {
            rates.follow(store.settings.ratePair)
        } onChange: { [weak self] in
            Task { @MainActor in self?.followRatePair() }
        }
    }

    /// The appearance setting, applied to the whole app
    private func followTheme() {
        withObservationTracking {
            NSApp.appearance = switch store.settings.theme {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.followTheme() }
        }
    }

    #if DEBUG
    /// Debug builds open on the pane named by `-debugPane earnings|breakdown|settings`
    private static var debugLaunchPane: Pane? {
        switch UserDefaults.standard.string(forKey: "debugPane") {
        case "earnings": .earnings
        case "breakdown": .breakdown
        case "settings": .settings
        default: nil
        }
    }
    #endif
}
