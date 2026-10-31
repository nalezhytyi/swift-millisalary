import Foundation

public enum Period: String, CaseIterable, Sendable {
    case hour, day, week, month, year
}

public struct PeriodEarnings: Equatable, Sendable {
    public var earned: Double
    public var total: Double
}

/// What decides which days are worked, and when
public struct WorkdaySettings: Equatable, Sendable {
    public var workingDays: Double
    public var workingHoursPerDay: Double
    /// nil: 09:00
    public var startHour: TimeOfDay?
    /// nil: start plus hours a day
    public var endHour: TimeOfDay?

    public init(
        workingDays: Double,
        workingHoursPerDay: Double,
        startHour: TimeOfDay?,
        endHour: TimeOfDay?
    ) {
        self.workingDays = workingDays
        self.workingHoursPerDay = workingHoursPerDay
        self.startHour = startHour
        self.endHour = endHour
    }
}

public struct EarningsSettings: Equatable, Sendable {
    public var monthlySalary: Double
    public var workday: WorkdaySettings
    /// Day of month (1-31); clamped to the month length
    public var payday: Int
    /// Multiplier from the salary currency to the display currency
    public var exchangeRate: Double

    public init(
        monthlySalary: Double,
        workday: WorkdaySettings,
        payday: Int,
        exchangeRate: Double
    ) {
        self.monthlySalary = monthlySalary
        self.workday = workday
        self.payday = payday
        self.exchangeRate = exchangeRate
    }
}

public struct WorkingWindow: Equatable, Sendable {
    public var start: Date
    public var end: Date
}

public struct EarningsSnapshot: Equatable, Sendable {
    public struct Rates: Equatable, Sendable {
        public var perSecond: Double
        public var perMinute: Double
        public var perHour: Double
        public var perDay: Double
    }

    public struct NextPayday: Equatable, Sendable {
        public var date: Date
        public var daysLeft: Int
        public var isToday: Bool
        public var amount: Double
    }

    public var hour: PeriodEarnings
    public var day: PeriodEarnings
    public var week: PeriodEarnings
    public var month: PeriodEarnings
    public var year: PeriodEarnings
    public var rates: Rates
    public var nextPayday: NextPayday

    public subscript(period: Period) -> PeriodEarnings {
        switch period {
        case .hour: hour
        case .day: day
        case .week: week
        case .month: month
        case .year: year
        }
    }
}

/// The earnings model, ported from calculations.ts in the Electron app and
/// kept equal to it by the parity tests. Days and months are the
/// calendar's (its time zone is the local one a JS Date would use), times
/// are whole milliseconds like a JS Date's, and the arithmetic runs in the
/// same order, so the results match to the bit.
public struct EarningsModel: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    private static let defaultStartMinutes: Double = 9 * 60

    /// Whether `date` is paid: a weekday while its month still has
    /// scheduled working days left
    public func isScheduledDay(_ date: Date, workingDays: Double) -> Bool {
        isBusinessDay(date)
            && Double(businessDays(from: startOfMonth(date), before: date))
            < safeWorkingDays(workingDays)
    }

    /// The working window of `day`: start to end, or start plus hours a
    /// day when the end isn't after the start (an overnight shift, or both
    /// times the same), which then runs into the next day
    public func workingWindow(on day: Date, _ workday: WorkdaySettings) -> WorkingWindow {
        let workingHoursPerDay = normalizeWorkingHoursPerDay(workday.workingHoursPerDay)
        let startMinutes = workday.startHour.map { Double($0.minutes) }
            ?? Self.defaultStartMinutes
        let endMinutes = workday.endHour.map { Double($0.minutes) }
            ?? startMinutes + workingHoursPerDay * 60
        let start = atMinutes(startMinutes, of: day)
        let end = endMinutes > startMinutes
            ? atMinutes(endMinutes, of: day)
            // dayjs adds fractional hours as milliseconds, which a JS Date
            // truncates to whole ones
            : Date(epochMilliseconds: (start.epochMilliseconds
                + workingHoursPerDay * 3_600_000).rounded(.towardZero))

        return WorkingWindow(start: start, end: end)
    }

    public func paydayInMonth(of month: Date, payday: Int) -> Date {
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)!.count
        return adding(days: min(payday, daysInMonth) - 1, to: startOfMonth(month))
    }

    public func nextPayday(from today: Date, payday: Int) -> Date {
        let startOfToday = calendar.startOfDay(for: today)
        let thisMonth = paydayInMonth(of: startOfToday, payday: payday)

        if !(thisMonth < startOfToday) {
            return thisMonth
        }

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth(startOfToday))!
        return paydayInMonth(of: nextMonth, payday: payday)
    }

    /// Business days are Mon-Fri, a day only counts while the month still
    /// has scheduled working days left, and a worked day earns
    /// monthlySalary / workingDays spread evenly over its working window.
    /// Week = Mon-Sun (total is 5 days); year = completed months in full
    /// plus the current month. All money outputs are multiplied by
    /// `exchangeRate`.
    public func earnings(at date: Date, _ settings: EarningsSettings) -> EarningsSnapshot {
        let now = Date(epochMilliseconds: date.epochMilliseconds)
        let nowMs = now.epochMilliseconds
        let monthlySalary = settings.monthlySalary
        let workday = settings.workday
        let safeWorkingDays = safeWorkingDays(workday.workingDays)
        let window = workingWindow(on: now, workday)
        let windowStart = window.start.epochMilliseconds
        let windowEnd = window.end.epochMilliseconds
        let workingDayMilliseconds = windowEnd - windowStart

        let dailySalary = monthlySalary / safeWorkingDays
        let millisecondSalary = workingDayMilliseconds > 0
            ? dailySalary / workingDayMilliseconds : 0
        let hourlySalary = millisecondSalary * 3600 * 1000

        let startOfToday = calendar.startOfDay(for: now)
        let scheduledToday = isScheduledDay(now, workingDays: workday.workingDays)

        let millisecondsPastToday = scheduledToday
            ? millisecondsPast(nowMs, start: windowStart, end: windowEnd) : 0
        let dayEarned = millisecondSalary * millisecondsPastToday

        let startOfHour = calendar.dateInterval(of: .hour, for: now)!.start.epochMilliseconds
        let millisecondsPastHour = scheduledToday
            ? max(0, min(nowMs, windowEnd) - max(startOfHour, windowStart)) : 0
        let hourEarned = millisecondSalary * millisecondsPastHour

        let startOfWeek = adding(days: -((weekday(now) + 6) % 7), to: startOfToday)
        var completedWeekDays = 0
        var date = startOfWeek
        while date < startOfToday {
            if isScheduledDay(date, workingDays: workday.workingDays) {
                completedWeekDays += 1
            }
            date = adding(days: 1, to: date)
        }

        let completedScheduledDays = min(
            Double(businessDays(from: startOfMonth(now), before: startOfToday)),
            safeWorkingDays
        )
        let monthEarned = min(
            monthlySalary,
            completedScheduledDays * dailySalary + dayEarned
        )

        let nextPaydayDate = nextPayday(from: now, payday: settings.payday)
        let daysLeft = dayDifference(nextPaydayDate, startOfToday)
        let completedMonths = Double(calendar.component(.month, from: now) - 1)

        let money = { (amount: Double) in amount * settings.exchangeRate }

        return EarningsSnapshot(
            hour: PeriodEarnings(earned: money(hourEarned), total: money(hourlySalary)),
            day: PeriodEarnings(earned: money(dayEarned), total: money(dailySalary)),
            week: PeriodEarnings(
                earned: money(Double(completedWeekDays) * dailySalary + dayEarned),
                total: money(5 * dailySalary)
            ),
            month: PeriodEarnings(earned: money(monthEarned), total: money(monthlySalary)),
            year: PeriodEarnings(
                earned: money(completedMonths * monthlySalary + monthEarned),
                total: money(12 * monthlySalary)
            ),
            rates: .init(
                perSecond: money(millisecondSalary * 1000),
                perMinute: money(millisecondSalary * 60 * 1000),
                perHour: money(hourlySalary),
                perDay: money(dailySalary)
            ),
            nextPayday: .init(
                date: nextPaydayDate,
                daysLeft: daysLeft,
                isToday: daysLeft == 0,
                amount: money(monthlySalary)
            )
        )
    }

    // MARK: - Calendar helpers, each the dayjs call it replaces

    private func safeWorkingDays(_ workingDays: Double) -> Double {
        workingDays > 0 ? workingDays : defaultWorkingDays
    }

    /// day(): 0 is Sunday
    private func weekday(_ date: Date) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    private func isBusinessDay(_ date: Date) -> Bool {
        let day = weekday(date)
        return day != 0 && day != 6
    }

    /// startOf('month')
    private func startOfMonth(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }

    /// add(n, 'day'): the same wall-clock time n calendar days later
    private func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    /// countBusinessDaysBeforeDate: Mon-Fri from `start`'s day up to, not
    /// including, `end`'s
    private func businessDays(from start: Date, before end: Date) -> Int {
        let endDay = calendar.startOfDay(for: end)
        var count = 0
        var date = calendar.startOfDay(for: start)

        while date < endDay {
            if isBusinessDay(date) { count += 1 }
            date = adding(days: 1, to: date)
        }

        return count
    }

    /// startOf('day').hour(h).minute(m): the hour may run past 23 into the
    /// next day, and fractional minutes are truncated, as a JS Date does
    private func atMinutes(_ minutes: Double, of day: Date) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = Int((minutes / 60).rounded(.down))
        components.minute = Int(minutes.truncatingRemainder(dividingBy: 60))
        return calendar.date(from: components)!
    }

    /// calculateMillisecondsPastToday
    private func millisecondsPast(_ now: Double, start: Double, end: Double) -> Double {
        if now > start && now < end {
            return now - start
        } else if !(now < end) {
            return end - start
        }
        return 0
    }

    /// a.diff(b, 'day'): whole days, corrected for a change of UTC offset
    /// in between and truncated toward zero
    private func dayDifference(_ a: Date, _ b: Date) -> Int {
        let zoneDelta = Double(
            calendar.timeZone.secondsFromGMT(for: b) - calendar.timeZone.secondsFromGMT(for: a)
        ) * 1000
        let days = (a.epochMilliseconds - b.epochMilliseconds - zoneDelta) / 86_400_000
        return Int(days.rounded(.towardZero))
    }
}

extension Date {
    /// Whole milliseconds since 1970, what a JS Date holds
    var epochMilliseconds: Double {
        (timeIntervalSince1970 * 1000).rounded()
    }

    init(epochMilliseconds: Double) {
        self.init(timeIntervalSince1970: epochMilliseconds / 1000)
    }
}
