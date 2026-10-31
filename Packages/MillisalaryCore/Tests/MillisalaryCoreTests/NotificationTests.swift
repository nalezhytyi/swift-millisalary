import Foundation
import Testing
@testable import MillisalaryCore

private let fivePM = Date(timeIntervalSince1970: 1_793_286_000)

private func endOfDay(_ key: String, at date: Date = fivePM) -> ScheduledNotification {
    ScheduledNotification(kind: .endOfDay, key: key, at: date)
}

@Test func nothingIsDueBeforeItsTime() {
    let due = NotificationTiming.due([endOfDay("end_of_day:2026-10-29")], at: fivePM.addingTimeInterval(-1), handled: [])
    #expect(due.send.isEmpty)
    #expect(due.handled.isEmpty)
}

@Test func aDueNotificationGoesOutOnce() {
    let scheduled = [endOfDay("end_of_day:2026-10-29")]
    let first = NotificationTiming.due(scheduled, at: fivePM, handled: [])
    #expect(first.send == scheduled)
    #expect(first.handled == ["end_of_day:2026-10-29"])

    let second = NotificationTiming.due(scheduled, at: fivePM.addingTimeInterval(30), handled: first.handled)
    #expect(second.send.isEmpty)
}

@Test func aLateOneGoesOutForThreeHoursThenIsOnlyMarked() {
    let scheduled = [endOfDay("end_of_day:2026-10-29")]
    #expect(NotificationTiming.due(scheduled, at: fivePM.addingTimeInterval(3 * 3600), handled: []).send == scheduled)

    let stale = NotificationTiming.due(scheduled, at: fivePM.addingTimeInterval(3 * 3600 + 1), handled: [])
    #expect(stale.send.isEmpty)
    #expect(stale.handled == ["end_of_day:2026-10-29"])
}

@Test func onlyTheLastTenKeysAreKept() {
    let handled = (1...10).map { "end_of_day:2026-10-\($0)" }
    let due = NotificationTiming.due([endOfDay("end_of_day:2026-10-29")], at: fivePM, handled: handled)
    #expect(due.handled.count == 10)
    #expect(due.handled.first == "end_of_day:2026-10-2")
    #expect(due.handled.last == "end_of_day:2026-10-29")
}

@Test func contentNamesTheDaysPayAndThePaycheck() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
    var settings = Settings()
    settings.monthlySalary = 22_000
    settings.payday = 29
    // 2026-10-29 00:30, an overnight window's end would make day.earned 0
    let earnings = EarningsModel(calendar: calendar)
        .earnings(at: Date(timeIntervalSince1970: 1_793_226_600), settings.earningsSettings(exchangeRate: 1))

    let endOfDay = NotificationContent(kind: .endOfDay, earnings: earnings, currency: "UAH")
    #expect(endOfDay.title == "Workday complete")
    #expect(endOfDay.body == "You earned 1 000,00 ₴.")

    let payday = NotificationContent(kind: .payday, earnings: earnings, currency: "UAH")
    #expect(payday.title == "It's payday")
    #expect(payday.body == "22 000,00 ₴ paycheck.")
}
