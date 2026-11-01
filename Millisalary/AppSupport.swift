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
    /// What the app's English text formats its dates and numbers in
    nonisolated static let english = Locale(identifier: "en_US")
}
