// The settings pane's edits, which keep the coupled schedule fields in step
// (settingsDraft.ts and the getNext* helpers of salaryForm.ts in the
// Electron app). Times are wall-clock "HH:mm", as stored.

extension Settings {
    /// Changing Start moves End forward by hours a day
    public mutating func setStartHour(_ start: TimeOfDay) {
        startHour = start.formatted
        endHour = MillisalaryCore.endHour(from: start, workingHoursPerDay: workingHoursPerDay).formatted
    }

    /// Changing End recomputes hours a day; an End before Start pulls Start
    /// back to it (and hours a day, with no time between them, fall back to 8)
    public mutating func setEndHour(_ end: TimeOfDay) {
        var start = TimeOfDay(parsing: startHour)
        if let current = start, end.minutes < current.minutes {
            start = end
            startHour = end.formatted
        }
        endHour = end.formatted
        workingHoursPerDay = MillisalaryCore.workingHoursPerDay(from: start, to: end)
    }

    /// Editing hours a day moves End
    public mutating func setWorkingHoursPerDay(_ hours: Double) {
        workingHoursPerDay = normalizeWorkingHoursPerDay(hours)
        if let start = TimeOfDay(parsing: startHour) {
            endHour = MillisalaryCore.endHour(from: start, workingHoursPerDay: workingHoursPerDay).formatted
        }
    }

    public mutating func setWorkingDays(_ days: Double) {
        workingDays = normalizeWorkingDays(days)
    }

    public mutating func setPayday(_ day: Double) {
        payday = normalizePayday(day)
    }
}
