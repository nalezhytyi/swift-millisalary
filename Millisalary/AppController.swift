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
    private var statusItem: StatusItemController?

    /// SwiftUI's way to open the main window (a `Window` scene), which the
    /// app menu's commands hand over: AppKit code like the menu bar item
    /// can't get it from a view's environment
    var openWindow: OpenWindowAction?

    func start() {
        // One window, no tabs (and no tab items in the View and Window menus)
        NSWindow.allowsAutomaticWindowTabbing = false
        ElectronSettingsImport.runIfNeeded(into: store)
        statusItem = StatusItemController(store: store) { [weak self] pane in
            self?.show(pane)
        }
        followTheme()
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
