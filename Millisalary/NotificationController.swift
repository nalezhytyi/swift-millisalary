import AppKit
import MillisalaryCore
import Observation
import UserNotifications
import os

/// The end-of-day and payday notifications (notifications.ts in the Electron
/// app): a check every 30 s, on wake and whenever the settings change sends
/// what `NotificationTiming` says is due. A check rather than notifications
/// handed to the system ahead of time: a late one past the 3 h grace is
/// dropped instead of arriving hours later, nothing needs rescheduling when
/// the settings, the rate or the clock change, and a Debug build's faked
/// clock drives it. The app is always running in the menu bar anyway
@Observable
final class NotificationController {
    /// Whether macOS lets the app show notifications, for Settings
    private(set) var authorization = UNAuthorizationStatus.notDetermined

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let rates: ExchangeRateStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let model = EarningsModel()
    @ObservationIgnored private let clicks: ClickHandler
    @ObservationIgnored private var handled: [String]
    @ObservationIgnored private var wantedNotifications = false

    private static let handledKey = "notificationsHandled"
    private static let checkInterval: TimeInterval = 30
    private nonisolated static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Millisalary", category: "notifications")

    /// `onClick` shows the main window. The delegate is set here, before
    /// the app finishes launching, as UserNotifications asks
    init(store: SettingsStore, rates: ExchangeRateStore, defaults: UserDefaults = .standard, onClick: @escaping @MainActor () -> Void) {
        self.store = store
        self.rates = rates
        self.defaults = defaults
        clicks = ClickHandler(onClick: onClick)
        // Remembered across launches, so a restart after the time has passed
        // doesn't send the same notification twice
        handled = defaults.stringArray(forKey: Self.handledKey) ?? []
        UNUserNotificationCenter.current().delegate = clicks
    }

    func start() {
        followSettings()

        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        // Notifications may have been allowed or turned off in System Settings
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAuthorization() }
        }
        refreshAuthorization()
    }

    /// Checks on every settings change, and asks for permission once a
    /// notification is wanted (at launch with the defaults, which have both on)
    private func followSettings() {
        withObservationTracking {
            let settings = store.settings
            let wanted = settings.notifyEndOfDay || settings.notifyPayday
            if wanted && !wantedNotifications {
                requestAuthorization()
            }
            wantedNotifications = wanted
            check()
        } onChange: { [weak self] in
            Task { @MainActor in self?.followSettings() }
        }
    }

    /// Sends what is due now
    private func check() {
        let settings = store.settings
        let now = Clock.now
        let due = NotificationTiming.due(
            model.scheduledNotifications(around: now, settings: settings),
            at: now,
            handled: handled
        )
        if due.handled != handled {
            handled = due.handled
            defaults.set(handled, forKey: Self.handledKey)
        }
        guard !due.send.isEmpty else { return }

        let display = settings.amountDisplay(rates)
        let earnings = settings.earnings(at: now, display, model: model)
        for notification in due.send {
            send(NotificationContent(kind: notification.kind, earnings: earnings, currency: display.currency), id: notification.key)
        }
    }

    private func send(_ content: NotificationContent, id: String) {
        let message = UNMutableNotificationContent()
        message.title = content.title
        message.body = content.body
        message.sound = .default

        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: message, trigger: nil)) { error in
            if let error {
                Self.log.error("\(id, privacy: .public) not shown: \(error.localizedDescription, privacy: .public)")
            } else {
                Self.log.info("\(id, privacy: .public) shown")
            }
        }
    }

    private func requestAuthorization() {
        Task {
            do {
                try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                Self.log.error("Authorization failed: \(error.localizedDescription, privacy: .public)")
            }
            refreshAuthorization()
        }
    }

    private func refreshAuthorization() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus != authorization {
                Self.log.info("Authorization: \(settings.authorizationStatus.rawValue, privacy: .public) (0 not determined, 1 denied, 2 authorized, 3 provisional), alerts \(settings.alertSetting.rawValue, privacy: .public)")
            }
            authorization = settings.authorizationStatus
        }
    }

    /// Opens Notifications in System Settings at this app
    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The notification center's delegate: a click shows the main window, and
/// a notification is shown even while the app is in front
private nonisolated final class ClickHandler: NSObject, UNUserNotificationCenterDelegate {
    private let onClick: @MainActor () -> Void

    init(onClick: @escaping @MainActor () -> Void) {
        self.onClick = onClick
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await onClick()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
