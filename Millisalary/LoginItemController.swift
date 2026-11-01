import AppKit
import MillisalaryCore
import Observation
import ServiceManagement
import os

/// Keeps the macOS login item in step with the `launchAtLogin` setting,
/// both ways (loginItem.ts in the Electron app): turning it on registers the
/// app with `SMAppService.mainApp`, off removes it, and switching the app
/// off in System Settings > General > Login Items turns the setting off at
/// the next launch. A setting that is on without ever having been applied
/// (imported from the Electron app, or written with `defaults write`)
/// registers the app at launch instead. Only a Release build registers
/// itself: a Debug build would leave a login item pointing into DerivedData
@Observable
final class LoginItemController {
    /// For Settings: `.requiresApproval` means the user still has to allow
    /// the item in System Settings
    private(set) var status = SMAppService.mainApp.status

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private var applied: Bool?

    private static let log = Logger(category: "login-item")
    /// In the defaults: whether the item has been in place since the app
    /// last removed it, so that its absence means the user removed it
    private static let registeredKey = "loginItemRegistered"

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
            reconcile()
        }
        followSettings()
        NotificationCenter.default.observe(NSApplication.didBecomeActiveNotification) { [weak self] in
            self?.status = SMAppService.mainApp.status
        }
    }

    /// At launch, before the setting is followed: an item in place turns
    /// the setting on; a missing one turns it off when it had been in place
    /// (the user removed it in System Settings), and is registered when it
    /// never was
    private func reconcile() {
        if isRegistered {
            itemWasRegistered = true
            if !store.settings.launchAtLogin {
                store.update { $0.launchAtLogin = true }
            }
        } else if !store.settings.launchAtLogin {
            itemWasRegistered = false
        } else if itemWasRegistered {
            Self.log.info("The login item is gone: turning the setting off")
            itemWasRegistered = false
            store.update { $0.launchAtLogin = false }
        } else {
            Self.log.info("The setting is on but the login item was never registered: registering")
            apply(true)
        }
    }

    private var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    private var itemWasRegistered: Bool {
        get { UserDefaults.standard.bool(forKey: Self.registeredKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.registeredKey) }
    }

    private func followSettings() {
        followChanges { [weak self] in
            guard let self else { return }
            let enabled = store.settings.launchAtLogin
            if enabled != applied {
                // The first pass only records the state the launch settled on
                if applied != nil {
                    apply(enabled)
                }
                applied = enabled
            }
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
            itemWasRegistered = enabled
        } catch {
            Self.log.error("\(enabled ? "Register" : "Unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        status = SMAppService.mainApp.status
        if isRegistered {
            itemWasRegistered = true
        }
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
