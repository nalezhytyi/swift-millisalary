import Foundation

enum Clock {
    /// The current time. A Debug build can start its clock at another
    /// moment with the launch argument `-debugNow "2026-10-29 13:30"` (local
    /// time), e.g. to watch a weekday's earnings tick on a weekend; it runs
    /// on from there
    static var now: Date {
        #if DEBUG
        Date.now.addingTimeInterval(debugShift)
        #else
        Date.now
        #endif
    }

    #if DEBUG
    private static let debugShift: TimeInterval = {
        guard let value = UserDefaults.standard.string(forKey: "debugNow") else { return 0 }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)?.timeIntervalSinceNow ?? 0
    }()
    #endif
}
