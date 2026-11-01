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
    @ObservationIgnored private let analytics: Analytics
    @ObservationIgnored private let showWindow: @MainActor () -> Void
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var clicks: ClickHandler?
    @ObservationIgnored private var handled: [String]
    /// The settings the last check went by, to tell what a change of them
    /// made due; nil until the first check at launch
    @ObservationIgnored private var checkedSettings: Settings?
    @ObservationIgnored private var wantedNotifications = false

    private static let handledKey = "notificationsHandled"
    private static let checkInterval: TimeInterval = 30
    private nonisolated static let log = Logger(category: "notifications")

    /// `showWindow` is what a click on an earnings notification does
    init(
        store: SettingsStore,
        rates: ExchangeRateStore,
        analytics: Analytics,
        defaults: UserDefaults = .standard,
        showWindow: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.rates = rates
        self.analytics = analytics
        self.defaults = defaults
        self.showWindow = showWindow
        // Remembered across launches, so a restart after the time has passed
        // doesn't send the same notification twice
        handled = defaults.stringArray(forKey: Self.handledKey) ?? []
    }

    /// Takes the notification center's clicks. Called before the app
    /// finishes launching, as UserNotifications asks
    func becomeDelegate() {
        guard clicks == nil else { return }
        let clicks = ClickHandler { [weak self] id, url in
            self?.clicked(id: id, url: url)
        }
        self.clicks = clicks
        UNUserNotificationCenter.current().delegate = clicks
    }

    /// A notification's id starts with its kind: "end_of_day:…", "payday:…"
    /// show the window, "update:<version>" opens the release page
    private func clicked(id: String, url: URL?) {
        let kind = String(id.prefix { $0 != ":" })
        if kind == "update" {
            analytics.track("update_notification_clicked", ["version": .string(String(id.dropFirst("update:".count)))])
        } else {
            analytics.track("notification_clicked", ["kind": .string(kind)])
        }
        if let url {
            NSWorkspace.shared.open(url)
        } else {
            showWindow()
        }
    }

    func start() {
        followSettings()
        Timer.repeating(every: Self.checkInterval, tolerance: 5) { [weak self] in self?.check() }
        NSWorkspace.shared.notificationCenter.observe(NSWorkspace.didWakeNotification) { [weak self] in
            self?.check()
        }
        // Notifications may have been allowed or turned off in System Settings
        NotificationCenter.default.observe(NSApplication.didBecomeActiveNotification) { [weak self] in
            self?.refreshAuthorization()
        }
        refreshAuthorization()
    }

    /// Checks on every settings change, and asks for permission once a
    /// notification is wanted (at launch with the defaults, which have both on)
    private func followSettings() {
        followChanges { [weak self] in
            guard let self else { return }
            let settings = store.settings
            let wanted = settings.notifyEndOfDay || settings.notifyPayday
            if wanted && !wantedNotifications {
                requestAuthorization()
            }
            wantedNotifications = wanted
            check()
        }
    }

    /// Sends what is due now
    private func check() {
        let settings = store.settings
        let now = Clock.now
        // Made for each check, in the time zone of the moment, rather than
        // relying on a long-lived calendar to follow a change of zone
        let model = EarningsModel()
        var previouslyScheduled: [ScheduledNotification]?
        if let checkedSettings, checkedSettings != settings {
            previouslyScheduled = model.scheduledNotifications(around: now, settings: checkedSettings)
        }
        let due = NotificationTiming.due(
            model.scheduledNotifications(around: now, settings: settings),
            at: now,
            handled: handled,
            previouslyScheduled: previouslyScheduled
        )
        checkedSettings = settings
        if due.handled != handled {
            handled = due.handled
            defaults.set(handled, forKey: Self.handledKey)
        }
        guard !due.send.isEmpty else { return }

        let display = settings.amountDisplay(rates)
        let earnings = settings.earnings(at: now, display, model: model)
        for notification in due.send {
            let content = NotificationContent(kind: notification.kind, earnings: earnings, currency: display.currency)
            send(title: content.title, body: content.body, id: notification.key)
        }
    }

    /// Any other notification, e.g. a new version; a click opens `url`
    /// instead of the window
    func announce(title: String, body: String, id: String, opening url: URL) {
        send(title: title, body: body, id: id, url: url)
    }

    private func send(title: String, body: String, id: String, url: URL? = nil) {
        let message = UNMutableNotificationContent()
        message.title = title
        message.body = body
        message.sound = .default
        if let url {
            message.userInfo = [ClickHandler.urlKey: url.absoluteString]
        }

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

/// The notification center's delegate: hands a click (the notification's
/// id, and the URL it opens if any) to the controller, and has a
/// notification shown even while the app is in front
private nonisolated final class ClickHandler: NSObject, UNUserNotificationCenterDelegate {
    static let urlKey = "url"
    private let onClick: @MainActor (String, URL?) -> Void

    init(onClick: @escaping @MainActor (String, URL?) -> Void) {
        self.onClick = onClick
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        let url = (request.content.userInfo[Self.urlKey] as? String).flatMap(URL.init(string:))
        await onClick(request.identifier, url)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
