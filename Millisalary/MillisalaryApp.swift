import MillisalaryCore
import SwiftUI

/// Started from main.swift, after its `--smoke-test` check
struct MillisalaryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let app = appDelegate.app

        // The one main window, opened at launch. Closing it leaves the app
        // in the menu bar and the Dock; AppController.show opens it again
        Window("Millisalary", id: AppController.mainWindowID) {
            MainView()
                .environment(app.store)
                .environment(app.navigation)
                .environment(app.ticker)
                .environment(app.rates)
                .environment(app.notifications)
                .environment(app.loginItem)
                .environment(app.face)
                .environment(app.splash)
                .environment(app.analytics)
        }
        // A first launch's size, tall enough for all of Breakdown without
        // scrolling; after that macOS restores the window's last frame
        .defaultSize(width: 860, height: 690)
        .windowResizability(.contentMinSize)

        // A window of its own (⌘,), as in most Mac apps; its tabs size it
        SwiftUI.Settings {
            SettingsView()
                .environment(app.store)
                .environment(app.navigation)
                .environment(app.rates)
                .environment(app.notifications)
                .environment(app.loginItem)
                .environment(app.analytics)
        }
        .commands {
            AppCommands(app: app)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        app.prepareLaunch(launchEvent: NSAppleEventManager.shared().currentAppleEvent)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.start()
    }

    /// A Dock click or a second launch brings the main window back, also
    /// when only the Settings window is open
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        app.show()
        return true
    }

    /// Closing the window leaves the app in the menu bar and the Dock
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// The application menu's own items; their shortcuts are the app's
private struct AppCommands: Commands {
    let app: AppController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        // The commands are built at launch whether or not the window is
        // open, so this is where AppController gets the window openers
        let _ = app.openWindow = openWindow
        let _ = app.openSettings = openSettings

        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { app.updates.checkFromMenu(source: .menu) }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { app.showSettings(source: .shortcut) }
                .keyboardShortcut(",")
        }

        CommandGroup(before: .toolbar) {
            Button("Toggle Sidebar") { app.navigation.toggleSidebar(source: .shortcut) }
                .keyboardShortcut("s", modifiers: [.control, .command])
            Divider()
            // A radio group that follows the selected period
            ForEach(Array(Period.allCases.enumerated()), id: \.element) { index, period in
                Toggle(SidebarItem.period(period).title, isOn: Binding {
                    app.store.settings.selectedPeriod == period
                } set: { _ in
                    app.showPeriod(period)
                })
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
            Divider()
            Button("Breakdown") { app.show(.breakdown) }
                .keyboardShortcut("i")
            Divider()
        }
    }
}
