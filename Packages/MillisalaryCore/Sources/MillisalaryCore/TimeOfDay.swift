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
    /// real times through, so that only matters for unvalidated input. Read
    /// by hand rather than with a Regex, which cost more than the earnings
    /// model itself on every tick
    public init?(parsing value: String) {
        let bytes = Array(value.utf8)
        guard bytes.count == 5, bytes[2] == UInt8(ascii: ":"),
              let hour = Self.twoDigits(bytes[0], bytes[1]),
              let minute = Self.twoDigits(bytes[3], bytes[4])
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    private static func twoDigits(_ tens: UInt8, _ ones: UInt8) -> Int? {
        let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
        guard digits.contains(tens), digits.contains(ones) else { return nil }
        return Int(tens - digits.lowerBound) * 10 + Int(ones - digits.lowerBound)
    }

    /// "HH:mm", as the settings store it
    public var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }
}
