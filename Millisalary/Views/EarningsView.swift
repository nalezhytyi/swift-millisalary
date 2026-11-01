import MillisalaryCore
import SwiftUI

/// A period of the Earnings section: the dial, a line on where the workday
/// stands, and the rates and the next payday under it, or, with no salary
/// yet, the form that sets one up
struct EarningsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        if store.settings.monthlySalary > 0 {
            LiveEarnings()
                .padding(.horizontal, 20)
                // The facts' Form adds its own 20 pt around the card
                .padding(.bottom, 4)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Nothing scrolls under the toolbar here, so it has no bar;
                // the setup form does scroll, and keeps it
                .toolbarBackground(.hidden, for: .windowToolbar)
        } else {
            SalarySetupView()
        }
    }
}

/// What the time changes, worked out on every tick of the Ticker (ten a
/// second) and handed down as just what each part shows, so a part whose
/// figures haven't changed (the labels, the facts at two decimals) isn't
/// redrawn: only the amount and the ring's fill change on most ticks
private struct LiveEarnings: View {
    @Environment(SettingsStore.self) private var store
    @Environment(ExchangeRateStore.self) private var rates
    @Environment(Ticker.self) private var ticker

    var body: some View {
        let settings = store.settings
        let display = settings.amountDisplay(rates)
        let now = ticker.now
        let model = EarningsModel()
        let earnings = settings.earnings(at: now, display, model: model)
        let period = settings.selectedPeriod
        let workday = WorkdayState(settings, at: now, model: model)

        VStack(spacing: 0) {
            // The dial and its line stay together, centred in the height the
            // facts leave
            VStack(spacing: 14) {
                EarningsDial(
                    earned: earnings[period].earned,
                    total: earnings[period].total,
                    currency: display.currency,
                    period: period,
                    scale: DialScale(period, workday, settings, at: now, model: model)
                )
                .frame(minWidth: 176, maxWidth: 384)
                Text(verbatim: workday.status(for: period, at: now))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.vertical, 16)
            .frame(maxHeight: .infinity)

            if !settings.dialFacts.isEmpty {
                FactsRow(cells: DialFactFigures(settings, display, earnings).cells(settings.dialFacts))
                    .equatable()
            }
        }
    }
}

/// Today's working window and whether it pays, as the earnings model sees
/// them, and when the next one starts
struct WorkdayState {
    let window: WorkingWindow
    let isScheduled: Bool
    let isEarning: Bool
    /// The next paid window's start after today's, and how many days on
    let next: (start: Date, days: Int)?

    private struct NextKey: Equatable {
        let today: Date
        let workday: WorkdaySettings
    }
    private static let nextMemo = DayMemo<NextKey, (start: Date, days: Int)?>()

    init(_ settings: MillisalaryCore.Settings, at now: Date, model: EarningsModel = EarningsModel()) {
        let workday = settings.workday
        window = model.workingWindow(on: now, workday)
        isScheduled = model.isScheduledDay(now, workingDays: settings.workingDays)
        isEarning = isScheduled && window.start <= now && now < window.end

        let today = model.calendar.startOfDay(for: now)
        next = Self.nextMemo.value(for: NextKey(today: today, workday: workday)) {
            (1...31).lazy.compactMap { days -> (start: Date, days: Int)? in
                let day = model.calendar.date(byAdding: .day, value: days, to: today)!
                guard model.isScheduledDay(day, workingDays: workday.workingDays) else { return nil }
                return (model.workingWindow(on: day, workday).start, days)
            }.first
        }
    }

    /// What the line under the dial depends on: it changes once a minute at
    /// most, and only then is the sentence looked up again, rather than on
    /// every tick
    private struct StatusKey: Equatable {
        let minutesLeft: Int?
        /// Monday is 1; 0 when the line doesn't count the day (not This Week)
        let weekday: Int
        let window: WorkingWindow
        let isScheduled: Bool
        let beforeStart: Bool
        let nextStart: Date?
        let nextDays: Int?
        let locale: Locale
    }
    private static let statusMemo = DayMemo<StatusKey, String>()

    /// "3 h 30 min left today, until 17:00", or when earning starts again.
    /// Each line is one text of the catalog, whole, the opening sentence
    /// included: a translation moves the parts about and inflects them
    func status(for period: Period, at now: Date) -> String {
        let key = StatusKey(
            minutesLeft: isEarning ? Int((window.end.timeIntervalSince(now) / 60).rounded(.up)) : nil,
            weekday: isEarning && period == .week ? (EarningsModel().calendar.component(.weekday, from: now) + 5) % 7 + 1 : 0,
            window: window,
            isScheduled: isScheduled,
            beforeStart: now < window.start,
            nextStart: next?.start,
            nextDays: next?.days,
            locale: .app
        )
        return Self.statusMemo.value(for: key) { status(key) }
    }

    private func status(_ key: StatusKey) -> String {
        if let minutesLeft = key.minutesLeft {
            let left = Self.duration(minutes: minutesLeft)
            if key.weekday > 0 {
                return String(localized: "Day \(key.weekday) of 5, \(left) left today")
            }
            return String(localized: "\(left) left today, until \(window.end.formatted(.clock))")
        }
        if isScheduled && key.beforeStart {
            return String(localized: "Earning starts today at \(window.start.formatted(.clock))")
        }
        guard let next else {
            return isScheduled ? String(localized: "Done for today.") : String(localized: "Day off.")
        }
        let time = next.start.formatted(.clock)
        switch next.days {
        case 1:
            return isScheduled
                ? String(localized: "Done for today. Earning resumes tomorrow at \(time)")
                : String(localized: "Day off. Earning resumes tomorrow at \(time)")
        case ..<7:
            let weekday = next.start.formatted(.dateTime.weekday(.wide).locale(.app))
            return isScheduled
                ? String(localized: "Done for today. Earning resumes \(weekday) at \(time)")
                : String(localized: "Day off. Earning resumes \(weekday) at \(time)")
        default:
            let date = next.start.formatted(.dateTime.day().month(.wide).locale(.app))
            return isScheduled
                ? String(localized: "Done for today. Earning resumes on \(date) at \(time)")
                : String(localized: "Day off. Earning resumes on \(date) at \(time)")
        }
    }

    /// "3 h 30 min", rounded up to the minute as a countdown is
    private static func duration(minutes: Int) -> String {
        switch (minutes / 60, minutes % 60) {
        case (0, let minutes): return String(localized: "\(minutes) min")
        case (let hours, 0): return String(localized: "\(hours) h")
        case (let hours, let minutes): return String(localized: "\(hours) h \(minutes) min")
        }
    }
}

/// One value kept until its key changes: what the Earnings pane works out
/// once a day (the next paid day, the month's paid days, each a loop of
/// calendar arithmetic) or once a minute (the line under the dial) rather
/// than on every 100 ms tick. The keys hold the
/// day or month as the model's calendar starts it, so a change of time zone
/// makes a new one
final class DayMemo<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?

    func value(for key: Key, _ make: () -> Value) -> Value {
        if let value, self.key == key {
            return value
        }
        let made = make()
        self.key = key
        value = made
        return made
    }
}

/// The facts chosen in Settings, in a row under the dial, the same for
/// every period; redrawn only when what one of them says changes
private struct FactsRow: View, Equatable {
    let cells: [DialFactCell]

    var body: some View {
        // A grouped Form's card, as Breakdown's rates are in; the Form is as
        // tall as its card and draws no background of its own here. Its
        // 20 pt margin stays: contentMargins (any placement) and
        // listRowInsets don't change it on macOS 27 (measured on captures,
        // 2026-11-01), so the pane allows for it
        Form {
            Section {
                DialFactCells(cells: cells)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}
