// The settings form's normalizers (salaryForm.ts in the Electron app)

public let defaultWorkingHoursPerDay: Double = 8
public let defaultWorkingDays: Double = 22

/// Working days a month, 1...31. Not rounded: a fractional value is kept
/// as it is, like the Electron app does
public func normalizeWorkingDays(_ value: Double) -> Double {
    guard value.isFinite, value > 0 else { return 1 }
    return min(value, 31)
}

/// Payday as a day of month, 1...31
public func normalizePayday(_ value: Double) -> Int {
    guard value.isFinite, value >= 1 else { return 1 }
    return Int(min(value.rounded(.down), 31))
}

/// Hours a day, up to 24; anything not above 0 is the default 8
public func normalizeWorkingHoursPerDay(_ value: Double) -> Double {
    value > 0 ? min(value, 24) : defaultWorkingHoursPerDay
}

/// Start plus hours a day, wrapping past midnight (getEndHourFromStart).
/// Added in whole milliseconds and cut to the minute, as the Electron app
/// does with a Date it then stores as "HH:mm": 09:00 + 8.33 h is 17:19
public func endHour(from start: TimeOfDay, workingHoursPerDay: Double) -> TimeOfDay {
    let milliseconds = (normalizeWorkingHoursPerDay(workingHoursPerDay) * 3_600_000).rounded(.towardZero)
    return TimeOfDay(hour: 0, minute: start.minutes + Int(milliseconds / 60_000))
}

/// Hours a day from Start to End, to two decimals; 8 when either is
/// missing or End isn't after Start (calculateWorkingHoursPerDayValue)
public func workingHoursPerDay(from start: TimeOfDay?, to end: TimeOfDay?) -> Double {
    guard let start, let end else { return defaultWorkingHoursPerDay }
    let hours = Double(end.minutes - start.minutes) / 60
    guard hours > 0 else { return defaultWorkingHoursPerDay }
    return (hours * 100).rounded() / 100
}
