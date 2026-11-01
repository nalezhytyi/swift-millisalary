import AppKit
import MillisalaryCore
import os

/// The update check (updates.ts in the Electron app): 15 s after launch and
/// then once a day it asks GitHub for the latest release and announces a
/// newer one once, with a notification that opens the release's page; Check
/// for Updates… in the menus always answers in a dialog. The app isn't
/// signed with a Developer ID, so it doesn't replace itself: the dmg is
/// installed by hand
final class UpdateChecker {
    private let notifications: NotificationController
    private let analytics: Analytics
    private let defaults: UserDefaults
    /// A menu check's fetch or dialog is still going
    private var isCheckingFromMenu = false

    private static let firstCheckDelay: TimeInterval = 15
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    /// The version the user was last told about, so the daily check doesn't
    /// announce the same release every day
    private static let notifiedKey = "updateNotifiedVersion"
    private nonisolated static let log = Logger(category: "updates")

    init(notifications: NotificationController, analytics: Analytics, defaults: UserDefaults = .standard) {
        self.notifications = notifications
        self.analytics = analytics
        self.defaults = defaults
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// GitHub's latest release of the repo in the Info.plist
    /// (`MillisalaryReleasesRepo`, set in project.yml); a Debug build can
    /// ask a test server instead with `-debugReleasesURL <url>`
    private static var releasesURL: URL? {
        #if DEBUG
        if let url = UserDefaults.standard.string(forKey: "debugReleasesURL").flatMap(URL.init(string:)) {
            return url
        }
        #endif
        return (Bundle.main.object(forInfoDictionaryKey: "MillisalaryReleasesRepo") as? String)
            .map(GitHubReleases.latestURL(repo:))
    }

    /// A Debug build has nothing to update, unless it's pointed at a test
    /// server
    private static var checksAutomatically: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "debugReleasesURL") != nil
        #else
        true
        #endif
    }

    func start() {
        guard Self.checksAutomatically else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstCheckDelay) { [weak self] in
            self?.checkQuietly()
        }
        Timer.repeating(every: Self.checkInterval, tolerance: 60 * 60) { [weak self] in self?.checkQuietly() }
    }

    /// Check for Updates… in the app menu (`.menu`) and the menu bar item's
    /// menu (`.tray`). A click while a check is still out (the request, or
    /// its dialog) only brings the app forward, so that dialog shows: one
    /// dialog answers both. The click is still reported, as the Electron
    /// app reported every one
    func checkFromMenu(source: ActionSource) {
        analytics.track("update_check_clicked", ["source": .string(source.rawValue)])
        guard !isCheckingFromMenu else {
            NSApp.activate()
            return
        }
        isCheckingFromMenu = true
        Task {
            show(await fetch())
            isCheckingFromMenu = false
        }
    }

    /// The automatic check stays quiet unless there's a version it hasn't
    /// announced
    private func checkQuietly() {
        Task {
            guard case .available(let release) = await fetch(),
                  defaults.string(forKey: Self.notifiedKey) != release.version.description
            else { return }
            defaults.set(release.version.description, forKey: Self.notifiedKey)
            analytics.track("update_available_notified", ["version": .string(release.version.description)])
            notifications.announce(
                title: String(localized: "Millisalary \(release.version.description) is available"),
                body: String(localized: "Click to open the download page."),
                id: "update:\(release.version)",
                opening: release.url
            )
        }
    }

    private func fetch() async -> ReleaseCheck {
        guard let url = Self.releasesURL else { return .failed }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result = GitHubReleases.check(status: status, data: data, current: Self.currentVersion)
            Self.log.info("\(url.absoluteString, privacy: .public): \(String(describing: result), privacy: .public)")
            return result
        } catch {
            Self.log.error("\(url.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private func show(_ result: ReleaseCheck) {
        let alert = NSAlert()
        switch result {
        case .available(let release):
            alert.messageText = String(localized: "Millisalary \(release.version.description) is available")
            alert.informativeText = String(localized: "You have \(Self.currentVersion).")
            alert.addButton(withTitle: String(localized: "Open Download Page"))
            alert.addButton(withTitle: String(localized: "Later"))
        case .current:
            alert.messageText = String(localized: "You're up to date")
            alert.informativeText = String(localized: "Millisalary \(Self.currentVersion) is the latest version.")
        case .failed:
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Couldn't check for updates")
            alert.informativeText = String(localized: "Check your internet connection and try again.")
        }

        // From the menu bar item the app may well be in the background
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, case .available(let release) = result {
            NSWorkspace.shared.open(release.url)
        }
    }
}
