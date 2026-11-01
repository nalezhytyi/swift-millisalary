import AppKit
import Observation
import os

/// Runs `apply` now, and again after every change to the observable values
/// it read, for as long as it reads any: a closure that holds its owner
/// weakly stops once the owner is gone
func followChanges(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking(apply) {
        Task { @MainActor in followChanges(apply) }
    }
}

extension Timer {
    /// Calls `action` every `interval` on the main run loop, in its common
    /// modes, so it keeps firing during a live resize and while a menu is
    /// open
    @discardableResult
    static func repeating(every interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated(action)
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

extension NotificationCenter {
    /// Calls `action` on the main thread whenever `name` is posted
    @discardableResult
    func observe(_ name: Notification.Name, object: AnyObject? = nil, _ action: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        addObserver(forName: name, object: object, queue: .main) { _ in
            MainActor.assumeIsolated(action)
        }
    }
}

extension Logger {
    /// A category of the app's log, under its bundle ID
    nonisolated init(category: String) {
        self.init(subsystem: Bundle.main.bundleIdentifier ?? "Millisalary", category: category)
    }
}

extension Locale {
    /// The language the app runs in: one of its translations, which macOS
    /// picks at launch from the preferred languages or System Settings'
    /// choice for Millisalary
    nonisolated static let appLanguage = Locale.LanguageCode(Bundle.main.preferredLocalizations.first ?? "en")

    /// What the app's text formats its dates in (weekdays, months, the
    /// time): the user's locale as it is now, its region and the overrides
    /// in Language & Region (24-hour time, the first weekday) included, in
    /// the app's language. `Locale.current` alone has the first preferred
    /// language, which may not be one the app has: an English app on a Mac
    /// set to German, English second, would name its days in German. Made
    /// again on every use (about a microsecond), so a change of region or
    /// clock while the app runs shows on the next tick
    nonisolated static var app: Locale {
        var components = Locale.Components(locale: .autoupdatingCurrent)
        components.languageComponents.languageCode = appLanguage
        return Locale(components: components)
    }
}

extension FormatStyle where Self == Date.FormatStyle {
    /// "17:00" or "5:00 PM", as the region writes it, in the app's language
    nonisolated static var clock: Date.FormatStyle {
        Date.FormatStyle.dateTime.hour().minute().locale(.app)
    }
}
