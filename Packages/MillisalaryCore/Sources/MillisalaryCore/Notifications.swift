import Foundation

public enum NotificationKind: String, Sendable {
    case endOfDay = "end_of_day"
    case payday
}

public struct ScheduledNotification: Equatable, Sendable {
    public let kind: NotificationKind
    /// One per kind per day: what makes a notification go out only once
    public let key: String
    public let at: Date
}

extension EarningsModel {
    /// The notifications around `now`, whether or not their time has come,
    /// on the schedule the earnings follow: the end of each paid day's
    /// working window, and payday at the start time. Yesterday's end is
    /// listed too, since an overnight window ends this morning. Nothing is
    /// scheduled without a salary (getScheduledNotifications in the Electron
    /// app)
    public func scheduledNotifications(around date: Date, settings: Settings) -> [ScheduledNotification] {
        guard settings.monthlySalary > 0 else { return [] }

        let now = Date(epochMilliseconds: date.epochMilliseconds)
        let workday = settings.workday
        var scheduled: [ScheduledNotification] = []

        if settings.notifyEndOfDay {
            for day in [adding(days: -1, to: now), now] where isScheduledDay(day, workingDays: settings.workingDays) {
                scheduled.append(ScheduledNotification(
                    kind: .endOfDay,
                    key: "end_of_day:\(dayKey(day))",
                    at: workingWindow(on: day, workday).end
                ))
            }
        }
        if settings.notifyPayday,
           calendar.isDate(paydayInMonth(of: now, payday: settings.payday), inSameDayAs: now) {
            scheduled.append(ScheduledNotification(
                kind: .payday,
                key: "payday:\(dayKey(now))",
                at: workingWindow(on: now, workday).start
            ))
        }

        return scheduled
    }

    /// "2026-10-29", the local date
    private func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

/// When a scheduled notification goes out (check() in the Electron app's
/// notifications.ts): once its time has come, once per key. One that is
/// late, because the Mac was asleep or the app wasn't running, still goes
/// out for 3 h; after that it's stale and only marked as handled
public enum NotificationTiming {
    public static let grace: TimeInterval = 3 * 60 * 60
    /// The handled keys remembered across launches; a key is a day, so a
    /// few days' worth is plenty
    public static let keptKeys = 10

    public static func due(
        _ scheduled: [ScheduledNotification],
        at now: Date,
        handled: [String]
    ) -> (send: [ScheduledNotification], handled: [String]) {
        var handled = handled
        var send: [ScheduledNotification] = []

        for notification in scheduled where !handled.contains(notification.key) && now >= notification.at {
            handled = Array((handled + [notification.key]).suffix(keptKeys))
            if now.timeIntervalSince(notification.at) <= grace {
                send.append(notification)
            }
        }

        return (send, handled)
    }
}

public struct NotificationContent: Equatable, Sendable {
    public let title: String
    public let body: String

    /// A finished workday earned its whole day's pay: `day.total`, since
    /// `day.earned` would be 0 for an overnight window that ended after
    /// midnight, today's not having begun
    public init(kind: NotificationKind, earnings: EarningsSnapshot, currency: String) {
        switch kind {
        case .endOfDay:
            title = "Workday complete"
            body = "You earned \(formatCurrency(earnings.day.total, currency: currency))."
        case .payday:
            title = "It's payday"
            body = "\(formatCurrency(earnings.nextPayday.amount, currency: currency)) paycheck."
        }
    }
}
