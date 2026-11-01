import MillisalaryCore
import SwiftUI

/// The live earnings in full: the next payday, each period's progress, the
/// rate and what it's worked out from
struct BreakdownView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(ExchangeRateStore.self) private var rates
    @Environment(Ticker.self) private var ticker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flyingMoney = FrameAnimation.flyingMoney()

    private static let english = Locale(identifier: "en_US")

    var body: some View {
        let settings = store.settings
        let display = settings.amountDisplay(rates)
        let earnings = settings.earnings(at: ticker.now, display)
        let currency = display.currency
        let money = { (amount: Double) in formatCurrency(amount, currency: currency) }

        Form {
            Section {
                payday(earnings.nextPayday, paycheck: money(earnings.nextPayday.amount))
            }

            Section("Earned so far") {
                // One grid rather than a row per period, so the bars and the
                // amounts line up in columns
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    ForEach(Period.allCases, id: \.self) { period in
                        let amount = earnings[period]
                        let progress = amount.total > 0 ? min(1, max(0, amount.earned / amount.total)) : 0
                        if period != Period.allCases.first {
                            Divider()
                        }
                        GridRow {
                            Text(period.label)
                            ProgressView(value: progress)
                                .accessibilityLabel("\(period.label) progress")
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(money(amount.earned))
                                    .fontWeight(.semibold)
                                Text("of \(money(amount.total))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .gridColumnAlignment(.trailing)
                            Text(progress, format: .percent.precision(.fractionLength(0)).locale(Self.english))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                        }
                        .monospacedDigit()
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack(spacing: 12) {
                    rate(formatCurrency(earnings.rates.perSecond, currency: currency, fractionDigits: 4), "Per second")
                    Divider()
                    rate(money(earnings.rates.perMinute), "Per minute")
                    Divider()
                    rate(money(earnings.rates.perHour), "Per hour")
                    Divider()
                    rate(money(earnings.rates.perDay), "Per day")
                }
                .padding(.vertical, 4)
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

    /// The next payday's date and paycheck, and a countdown to it
    private func payday(_ payday: EarningsSnapshot.NextPayday, paycheck: String) -> some View {
        HStack(spacing: 14) {
            // Holds still on frame 0 under Reduce Motion
            AnimatedFrames(animation: flyingMoney, paused: reduceMotion)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next payday")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(
                    payday.date,
                    format: .dateTime.weekday(.wide).month(.wide).day().locale(Self.english)
                )
                .font(.title2.weight(.semibold))
                Text("Paycheck \(Text(paycheck).fontWeight(.medium).foregroundStyle(.primary))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                if payday.isToday {
                    Text("Today")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("\(payday.daysLeft)")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                    Text(payday.daysLeft == 1 ? "day left" : "days left")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func rate(_ amount: String, _ label: String) -> some View {
        FigureCell(value: Text(amount), label: label)
    }

    /// What the rate is worked out from: the salary, the paid days and today's
    /// working hours
    /// The rate in use when the currencies differ, or why there's none yet
    private func exchangeRateNote(_ pair: CurrencyPair, _ display: AmountDisplay) -> String? {
        guard !pair.isSameCurrency else { return nil }
        guard let rate = display.rate(for: pair) else {
            return "Amounts are in \(pair.from) until the \(pair.from) to \(pair.to) exchange rate arrives."
        }
        return "1 \(pair.from) = \(rate) \(pair.to)"
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
        let days = settings.workingDays.formatted(.number.precision(.fractionLength(0...2)))
        let window = EarningsModel().workingWindow(on: Clock.now, settings.workday)
        let hours = Date.FormatStyle.dateTime.hour().minute()
        Label(
            "\(salary) a month over \(days) working \(settings.workingDays == 1 ? "day" : "days"), "
                + "paid evenly from \(window.start.formatted(hours)) to \(window.end.formatted(hours)), Monday to Friday.",
            systemImage: "calendar"
        )
    }
}

/// A figure and what it is, centred in one of a row of cells split by
/// dividers in a Form card: Breakdown's rates and the facts under the
/// Earnings dial
struct FigureCell: View {
    let value: Text
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            value
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
