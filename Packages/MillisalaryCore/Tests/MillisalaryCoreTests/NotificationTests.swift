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

// A check after a change of settings: what the old settings scheduled
// around `now` tells the notifications the change made due

private let kyiv: EarningsModel = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
    return EarningsModel(calendar: calendar)
}()

/// 22 000 a month, 09:00-17:00, both notifications on
private func settings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
    var settings = Settings()
    settings.monthlySalary = 22_000
    change(&settings)
    return settings
}

private func check(at now: Date, _ settings: Settings, before: Settings?) -> (send: [ScheduledNotification], handled: [String]) {
    NotificationTiming.due(
        kyiv.scheduledNotifications(around: now, settings: settings),
        at: now,
        handled: [],
        previouslyScheduled: before.map { kyiv.scheduledNotifications(around: now, settings: $0) }
    )
}

// fivePM is Thursday 2026-10-29, 17:00 in Kyiv
private let halfPastSeven = fivePM.addingTimeInterval(2.5 * 3600)

@Test func turningEndOfDayOnAfterTheEndOnlyMarksIt() {
    let due = check(at: halfPastSeven, settings(), before: settings { $0.notifyEndOfDay = false })
    #expect(due.send.isEmpty)
    #expect(due.handled.contains("end_of_day:2026-10-29"))
}

@Test func movingTheEndBeforeNowOnlyMarksIt() {
    let sevenPM = fivePM.addingTimeInterval(2 * 3600)
    let due = check(at: sevenPM, settings { $0.endHour = "18:00" }, before: settings { $0.endHour = "20:00" })
    #expect(due.send.isEmpty)
    #expect(due.handled.contains("end_of_day:2026-10-29"))
}

@Test func anUnrelatedChangeStillSendsWhatWasDue() {
    // The 30 s check hadn't come to it yet
    let due = check(at: fivePM.addingTimeInterval(10), settings { $0.theme = .dark }, before: settings())
    #expect(due.send.map(\.key) == ["end_of_day:2026-10-29"])
}

@Test func turningPaydayOnAfterItsTimeOnlyMarksIt() {
    let tenAM = fivePM.addingTimeInterval(-7 * 3600)
    let paydayToday = settings {
        $0.payday = 29
        $0.notifyEndOfDay = false
    }
    var paydayOff = paydayToday
    paydayOff.notifyPayday = false

    let due = check(at: tenAM, paydayToday, before: paydayOff)
    #expect(due.send.isEmpty)
    #expect(due.handled == ["payday:2026-10-29"])

    // Without a change it's an hour late, and still goes out
    #expect(check(at: tenAM, paydayToday, before: nil).send.map(\.key) == ["payday:2026-10-29"])
}

@Test func withoutPreviousSettingsALateOneStillGoesOut() {
    // At launch, or with the same settings as the last check
    let due = check(at: halfPastSeven, settings(), before: nil)
    #expect(due.send.map(\.key) == ["end_of_day:2026-10-29"])
    #expect(check(at: halfPastSeven, settings(), before: settings()).send == due.send)
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
