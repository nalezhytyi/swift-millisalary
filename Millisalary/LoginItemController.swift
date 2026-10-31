import AppKit
import MillisalaryCore
import Observation
import ServiceManagement
import os

/// Keeps the macOS login item in step with the `launchAtLogin` setting,
/// both ways (loginItem.ts in the Electron app): turning it on registers the
/// app with `SMAppService.mainApp`, off removes it, and switching the app
/// off in System Settings > General > Login Items turns the setting off at
/// the next launch. Only a Release build registers itself: a Debug build
/// would leave a login item pointing into DerivedData
@Observable
final class LoginItemController {
    /// For Settings: `.requiresApproval` means the user still has to allow
    /// the item in System Settings
    private(set) var status = SMAppService.mainApp.status

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private var applied: Bool?

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Millisalary", category: "login-item")

    static var isManaged: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    init(store: SettingsStore) {
        self.store = store
    }

    func start() {
        if Self.isManaged {
            let registered = status == .enabled || status == .requiresApproval
            if registered != store.settings.launchAtLogin {
                store.update { $0.launchAtLogin = registered }
            }
        }
        followSettings()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.status = SMAppService.mainApp.status }
        }
    }

    private func followSettings() {
        withObservationTracking {
            let enabled = store.settings.launchAtLogin
            if enabled != applied {
                // The first pass only records the state the launch found
                if applied != nil {
                    apply(enabled)
                }
                applied = enabled
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.followSettings() }
        }
    }

    private func apply(_ enabled: Bool) {
        guard Self.isManaged else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.log.error("\(enabled ? "Register" : "Unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        status = SMAppService.mainApp.status
    }

    /// Whether the system started the app at login, so it should start in
    /// the menu bar only; never without the setting on. A login item's
    /// launch event says so where macOS still sets it; otherwise, like the
    /// Electron app (macOS 13+ gives a login item no arguments), the app
    /// counts as started at login when it began within 90 s of this user's
    /// loginwindow, which restarts with every login. A manual launch in the
    /// first moments after logging in is the one case it gets wrong, and the
    /// Dock icon still opens the window
    static func wasLaunchedAtLogin(launchEvent: NSAppleEventDescriptor?, settingOn: Bool) -> Bool {
        #if DEBUG
        // `-debugLaunchedAtLogin YES` starts as if at login
        if UserDefaults.standard.bool(forKey: "debugLaunchedAtLogin") { return true }
        #endif
        guard settingOn else { return false }
        if launchEvent?.eventID == kAEOpenApplication,
           launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }
        guard let loginWindow = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.loginwindow").first,
            let loginStart = startTime(of: loginWindow.processIdentifier),
            let appStart = startTime(of: getpid())
        else { return false }
        return appStart.timeIntervalSince(loginStart) < 90
    }

    private static func startTime(of pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let time = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000)
    }
}
