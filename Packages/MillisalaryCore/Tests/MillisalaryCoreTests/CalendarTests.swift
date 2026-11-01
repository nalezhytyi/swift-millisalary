import Foundation
import Testing
@testable import MillisalaryCore

// The default model is the app's: Gregorian, as a JS Date always is, in the
// local time zone of wherever the tests run. These can't switch the
// system calendar, so they compare it with a model on the Hebrew calendar,
// whose months are what Language & Region would have given it before

private func local(_ identifier: Calendar.Identifier) -> Calendar {
    var calendar = Calendar(identifier: identifier)
    calendar.timeZone = .current
    return calendar
}

// Thursday 2026-10-29, 08:00 local time: before the workday, so today has
// earned nothing yet and every amount is whole days
private let thursdayMorning = local(.gregorian).date(
    from: DateComponents(year: 2026, month: 10, day: 29, hour: 8)
)!

@Test func theDefaultModelIsGregorianInTheLocalTimeZone() {
    let calendar = EarningsModel().calendar
    #expect(calendar.identifier == .gregorian)
    // The zone that follows the system's, not a copy of today's
    #expect(calendar.timeZone == .autoupdatingCurrent)
}

@Test func monthsAreGregorianWhateverTheSystemCalendar() {
    var settings = Settings()
    settings.monthlySalary = 22_000
    let earningsSettings = settings.earningsSettings(exchangeRate: 1)
    let gregorian = EarningsModel()
    // Heshvan 5787 began on Monday 12 October
    let hebrew = EarningsModel(calendar: local(.hebrew))

    let october1 = local(.gregorian).date(from: DateComponents(year: 2026, month: 10, day: 1))!
    #expect(gregorian.paydayInMonth(of: thursdayMorning, payday: 1) == october1)
    #expect(hebrew.paydayInMonth(of: thursdayMorning, payday: 1) != october1)

    // 20 working days of October before the 29th, and 9 months before it
    let earnings = gregorian.earnings(at: thursdayMorning, earningsSettings)
    #expect(earnings.month.earned == 20_000)
    #expect(earnings.year.earned == 218_000)
    let hebrewEarnings = hebrew.earnings(at: thursdayMorning, earningsSettings)
    #expect(hebrewEarnings.month.earned != 20_000)
    #expect(hebrewEarnings.year.earned != 218_000)

    let keys = gregorian.scheduledNotifications(around: thursdayMorning, settings: settings).map(\.key)
    #expect(keys == ["end_of_day:2026-10-28", "end_of_day:2026-10-29"])
    #expect(hebrew.scheduledNotifications(around: thursdayMorning, settings: settings).map(\.key) != keys)
}

// The paid days are counted from the number of days since the 1st and the
// weekday it was, rather than by stepping through them as calculations.ts
// does. Every day of two years, at noon, against that stepping, in zones
// whose DST changes come at midnight (Santiago: the day starts at 01:00)
// or at night (Kyiv, New York), which the parity fixture doesn't all have
@Test(arguments: ["America/Santiago", "Europe/Kyiv", "America/New_York", "Asia/Kolkata"])
func paidDaysCountedLikeTheSteppingTheyReplace(zone: String) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    let model = EarningsModel(calendar: calendar)

    /// countBusinessDaysBeforeDate, a day at a time
    func stepped(before date: Date) -> Int {
        let end = calendar.startOfDay(for: date)
        var day = calendar.dateInterval(of: .month, for: date)!.start
        var count = 0
        while day < end {
            let weekday = calendar.component(.weekday, from: day)
            if weekday != 1 && weekday != 7 { count += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return count
    }

    var day = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
    let end = calendar.date(from: DateComponents(year: 2028, month: 1, day: 1))!
    while day < end {
        let weekday = calendar.component(.weekday, from: day)
        let isWeekday = weekday != 1 && weekday != 7
        let before = Double(stepped(before: day))
        // Paid exactly while the days before it are fewer than the month's
        #expect(model.isScheduledDay(day, workingDays: before + 1) == isWeekday, "\(day)")
        #expect(!model.isScheduledDay(day, workingDays: max(1, before)) || before == 0, "\(day)")
        day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
}
