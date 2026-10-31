import Testing
@testable import MillisalaryCore

private func changes(_ edit: (inout Settings) -> Void) -> [AnalyticsEvent] {
    var after = Settings()
    edit(&after)
    return AnalyticsEvent.settingsChanges(from: Settings(), to: after)
}

@Test func nothingChangedNothingReported() {
    #expect(changes { _ in }.isEmpty)
}

@Test func theSalaryIsReportedWithItsAmount() {
    #expect(changes { $0.monthlySalary = 54321 } == [
        AnalyticsEvent("salary_input_blurred", ["salary_value": .number(54321), "has_salary_value": .bool(true)]),
    ])
}

@Test func movingStartReportsStartAndEnd() {
    #expect(changes { $0.setStartHour(TimeOfDay(hour: 10, minute: 0)) }.map(\.name) == [
        "workday_start_time_changed", "workday_end_time_changed",
    ])
    #expect(changes { $0.setStartHour(TimeOfDay(hour: 10, minute: 0)) }.first?.properties == ["start_time": .string("10:00")])
}

@Test func movingEndReportsEndAndHoursADay() {
    #expect(changes { $0.setEndHour(TimeOfDay(hour: 18, minute: 30)) } == [
        AnalyticsEvent("working_hours_per_day_changed", ["working_hours_per_day": .number(9.5)]),
        AnalyticsEvent("workday_end_time_changed", ["end_time": .string("18:30")]),
    ])
}

@Test func eachSwitchHasItsEvent() {
    #expect(changes { $0.notifyPayday = false } == [
        AnalyticsEvent("notifications_changed", ["end_of_day": .bool(true), "payday": .bool(false)]),
    ])
    #expect(changes { $0.menuBarAmount = .selected } == [
        AnalyticsEvent("menu_bar_display_changed", ["shown": .bool(true), "amount": .string("selected")]),
    ])
    #expect(changes { $0.launchAtLogin = true } == [AnalyticsEvent("launch_at_login_changed", ["enabled": .bool(true)])])
    #expect(changes { $0.theme = .dark } == [AnalyticsEvent("theme_changed", ["theme": .string("dark")])])
}

@Test func pickersReportTheirValues() {
    #expect(changes {
        $0.monthlySalaryCurrency = "EUR"
        $0.earningsCurrency = "PLN"
        $0.setWorkingDays(20)
        $0.setPayday(25)
    } == [
        AnalyticsEvent("salary_currency_changed", ["currency": .string("EUR")]),
        AnalyticsEvent("earnings_currency_changed", ["currency": .string("PLN")]),
        AnalyticsEvent("working_days_changed", ["working_days": .number(20)]),
        AnalyticsEvent("payday_changed", ["payday": .number(25)]),
    ])
}
