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
