import MillisalaryCore
import SwiftUI

/// The live earnings in full: the next payday, each period's progress, the
/// rate and what it's worked out from. Worked out on every tick, and handed
/// to each part as the text it shows, so a part is only redrawn when that
/// changes: at two decimals most ticks change nothing on screen
struct BreakdownView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(ExchangeRateStore.self) private var rates
    @Environment(Ticker.self) private var ticker
    @State private var flyingMoney = FrameAnimation.flyingMoney()

    var body: some View {
        let settings = store.settings
        let display = settings.amountDisplay(rates)
        let earnings = settings.earnings(at: ticker.now, display)
        let money = { (amount: Double) in formatCurrency(amount, currency: display.currency) }

        Form {
            Section {
                PaydayCard(
                    date: earnings.nextPayday.date,
                    daysLeft: earnings.nextPayday.isToday ? nil : earnings.nextPayday.daysLeft,
                    paycheck: money(earnings.nextPayday.amount),
                    animation: flyingMoney
                )
                .equatable()
            }

            Section("Earned so far") {
                EarnedGrid(rows: Period.allCases.map { EarnedGrid.Row(earnings[$0], label: $0.label, money: money) })
                    .equatable()
            }

            Section {
                // The same cells as the facts under the dial
                DialFactCells(cells: DialFactFigures(settings, display, earnings).cells([.perSecond, .perMinute, .perHour, .perDay]))
                    .equatable()
            } header: {
                Text("Your rate")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    ScheduleLine()
                    if let exchange = exchangeRateNote(settings.ratePair, display) {
                        Label(exchange, systemImage: "arrow.left.arrow.right")
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { flyingMoney.load() }
        .onDisappear { flyingMoney.unload() }
    }

    /// The rate in use when the currencies differ, or why there's none yet
    private func exchangeRateNote(_ pair: CurrencyPair, _ display: AmountDisplay) -> String? {
        guard !pair.isSameCurrency else { return nil }
        guard let rate = display.rate(for: pair) else {
            return String(localized: "Amounts are in \(pair.from) until the \(pair.from) to \(pair.to) exchange rate arrives.")
        }
        return "1 \(pair.from) = \(rate) \(pair.to)"
    }
}

/// The next payday's date and paycheck, and a countdown to it
private struct PaydayCard: View, Equatable {
    let date: Date
    /// nil on payday itself
    let daysLeft: Int?
    let paycheck: String
    let animation: FrameAnimation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            // Holds still on frame 0 under Reduce Motion
            AnimatedFrames(animation: animation, paused: reduceMotion)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next payday")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(date, format: .dateTime.weekday(.wide).month(.wide).day().locale(.app))
                    .font(.title2.weight(.semibold))
                Text("Paycheck \(Text(verbatim: paycheck).fontWeight(.medium).foregroundStyle(.primary))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                if let daysLeft {
                    Text(daysLeft, format: .number)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                    // The number is the big figure above, so the text has no
                    // plural of its own: English picks its own, a translation
                    // may not need either
                    Text(daysLeft == 1 ? "day left" : "days left")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Today")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 6)
    }

    static func == (a: Self, b: Self) -> Bool {
        a.date == b.date && a.daysLeft == b.daysLeft && a.paycheck == b.paycheck && a.animation === b.animation
    }
}

/// Each period's progress: one grid rather than a row per period, so the
/// bars and the amounts line up in columns
private struct EarnedGrid: View, Equatable {
    struct Row: Equatable {
        let label: String
        /// In steps of 0.1%, a fraction of a pixel on the bar, so the bars
        /// aren't redrawn on every tick
        let bar: Double
        let earned: String
        let total: String
        let percent: String

        init(_ amount: PeriodEarnings, label: String, money: (Double) -> String) {
            let progress = amount.total > 0 ? min(1, max(0, amount.earned / amount.total)) : 0
            self.label = label
            bar = (progress * 1000).rounded(.down) / 1000
            earned = money(amount.earned)
            total = money(amount.total)
            percent = progress.formatted(.percent.precision(.fractionLength(0)).locale(.app))
        }
    }

    let rows: [Row]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider()
                }
                GridRow {
                    Text(verbatim: row.label)
                    ProgressView(value: row.bar)
                        .accessibilityLabel("\(row.label) progress")
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: row.earned)
                            .fontWeight(.semibold)
                        Text("of \(row.total)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .gridColumnAlignment(.trailing)
                    Text(verbatim: row.percent)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                }
                .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

/// What the rate is worked out from: the salary, the paid days and today's
/// working hours. Its own view, off the ticks: it only changes with the
/// settings
private struct ScheduleLine: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        let settings = store.settings
        let salary = formatCurrency(settings.monthlySalary, currency: settings.monthlySalaryCurrency)
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
        let days = settings.workingDays.formatted(style)
        let window = EarningsModel().workingWindow(on: Clock.now, settings.workday)
        let from = window.start.formatted(.clock)
        let to = window.end.formatted(.clock)
        // English says "1 working day" for what shows as 1 (1.004 included)
        // and "days" for the rest; a translation is the same for both
        let sentence = days == 1.0.formatted(style)
            ? String(localized: "\(salary) a month over \(days) working day, \(from) to \(to), Mon–Fri.")
            : String(localized: "\(salary) a month over \(days) working days, \(from) to \(to), Mon–Fri.")
        Label(sentence, systemImage: "calendar")
    }
}
