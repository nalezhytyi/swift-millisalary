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

    /// "3 h 30 min left today, until 17:00", or when earning starts again
    func status(for period: Period, at now: Date) -> String {
        let time = Date.FormatStyle.dateTime.hour().minute()
        if isEarning {
            let left = Self.duration(window.end.timeIntervalSince(now))
            if period == .week {
                let weekday = (EarningsModel().calendar.component(.weekday, from: now) + 5) % 7 + 1
                return "Day \(weekday) of 5, \(left) left today"
            }
            return "\(left) left today, until \(window.end.formatted(time))"
        }
        if isScheduled && now < window.start {
            return "Earning starts today at \(window.start.formatted(time))"
        }
        let opening = isScheduled ? "Done for today." : "Day off."
        guard let next else { return opening }
        let when = switch next.days {
        case 1: "tomorrow"
        case ..<7: next.start.formatted(.dateTime.weekday(.wide).locale(.english))
        default: "on " + next.start.formatted(.dateTime.day().month(.wide).locale(.english))
        }
        return "\(opening) Earning resumes \(when) at \(next.start.formatted(time))"
    }

    /// "3 h 30 min", rounded up to the minute as a countdown is
    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        switch (minutes / 60, minutes % 60) {
        case (0, let minutes): return "\(minutes) min"
        case (let hours, 0): return "\(hours) h"
        case (let hours, let minutes): return "\(hours) h \(minutes) min"
        }
    }
}

/// One value kept until its key changes: what the Earnings pane works out
/// once a day (the next paid day, the month's paid days, each a loop of
/// calendar arithmetic) rather than on every 100 ms tick. The keys hold the
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
