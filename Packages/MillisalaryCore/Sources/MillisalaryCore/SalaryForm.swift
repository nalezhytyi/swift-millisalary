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
