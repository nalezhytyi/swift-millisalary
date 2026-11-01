import Foundation
import Testing
@testable import MillisalaryCore

private let model: EarningsModel = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
    return EarningsModel(calendar: calendar)
}()

private func settings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
    var settings = Settings()
    settings.monthlySalary = 22_000
    settings.workingDays = 22
    settings.startHour = "09:00"
    settings.endHour = "17:00"
    change(&settings)
    return settings
}

// Thursday 2026-10-29, 13:30 in Kyiv: 4.5 of 8 hours of 1 000 a day
private let thursdayAfternoon = model.calendar.date(
    from: DateComponents(year: 2026, month: 10, day: 29, hour: 13, minute: 30)
)!

// The tests pin the language: without one the rows follow the preferred
// languages of whoever runs them
private func content(_ settings: Settings, language: String = "en") -> MenuBarContent {
    let earnings = model.earnings(at: thursdayAfternoon, settings.earningsSettings(exchangeRate: 1))
    return MenuBarContent(settings: settings, earnings: earnings, currency: "UAH", locale: Locale(identifier: language))
}

@Test func titleIsTodaysEarningsByDefault() {
    #expect(content(settings()).title == "562,50 ₴")
}

@Test func titleFollowsTheSelectedPeriodWhenAsked() {
    let selected = settings {
        $0.menuBarAmount = .selected
        $0.selectedPeriod = .week
    }
    // Mon-Wed in full plus Thursday so far
    #expect(content(selected).title == "3 562,50 ₴")

    // The selected period only counts when the menu bar is set to follow it
    #expect(content(settings { $0.selectedPeriod = .week }).title == "562,50 ₴")
}

@Test func rowsListEveryPeriod() {
    #expect(content(settings()).rows == [
        "This hour: 62,50 ₴",
        "Today: 562,50 ₴",
        "This week: 3 562,50 ₴",
        // 20 working days of October before the 29th
        "This month: 20 562,50 ₴",
        "This year: 218 562,50 ₴",
    ])
}

@Test func rowsInUkrainian() {
    #expect(content(settings(), language: "uk").rows == [
        "Ця година: 62,50 ₴",
        "Сьогодні: 562,50 ₴",
        "Цей тиждень: 3 562,50 ₴",
        "Цей місяць: 20 562,50 ₴",
        "Цей рік: 218 562,50 ₴",
    ])
    // The amount itself is formatted the same in either language
    #expect(content(settings(), language: "uk").title == "562,50 ₴")
}

@Test func nothingButTheIconWithoutASalary() {
    let empty = MenuBarContent(settings: settings(), earnings: nil, currency: "UAH")
    #expect(empty.title.isEmpty)
    #expect(empty.rows.isEmpty)
}
