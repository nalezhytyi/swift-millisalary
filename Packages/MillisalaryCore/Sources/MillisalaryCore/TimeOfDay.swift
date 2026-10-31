import Foundation

/// A wall-clock time without a date: what the settings keep as "HH:mm" for
/// the start and end of the working day
public struct TimeOfDay: Hashable, Sendable {
    /// Minutes since midnight, 0..<1440
    public let minutes: Int

    public init(hour: Int, minute: Int) {
        let total = (hour * 60 + minute) % 1440
        minutes = total < 0 ? total + 1440 : total
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    /// Reads "HH:mm" (exactly two digits each) like parseTimeInputValue in
    /// the Electron app: values out of range roll over the way a JS Date's
    /// setHours does, so "25:99" is 02:39. The settings validator only lets
    /// real times through, so that only matters for unvalidated input
    public init?(parsing value: String) {
        guard let match = value.wholeMatch(of: /([0-9]{2}):([0-9]{2})/),
              let hour = Int(match.1), let minute = Int(match.2)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    /// "HH:mm", as the settings store it
    public var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }
}
