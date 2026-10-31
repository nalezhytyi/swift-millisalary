import MillisalaryCore
import SwiftUI

/// The live earnings in full: the next payday, each period's progress and
/// the rate
struct BreakdownView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(Ticker.self) private var ticker

    private static let english = Locale(identifier: "en_US")

    var body: some View {
        let settings = store.settings
        let earnings = settings.earnings(at: ticker.now)
        let currency = settings.displayCurrency
        let money = { (amount: Double) in formatCurrency(amount, currency: currency) }

        Form {
            Section {
                HStack(spacing: 12) {
                    Image(.moneyFace)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next payday")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(
                            earnings.nextPayday.date,
                            format: .dateTime.weekday(.wide).month(.wide).day().locale(Self.english)
                        )
                        .fontWeight(.semibold)
                        Text("\(money(earnings.nextPayday.amount)) paycheck")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(daysLeft(earnings.nextPayday.daysLeft))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Section("Earned so far") {
                ForEach(Period.allCases, id: \.self) { period in
                    let amount = earnings[period]
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(period.label)
                            Spacer()
                            Text(money(amount.earned))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                            Text("of \(money(amount.total))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                        ProgressView(value: amount.total > 0 ? min(1, max(0, amount.earned / amount.total)) : 0)
                            .accessibilityLabel("\(period.label) progress")
                    }
                }
            }

            Section {
                rate("Per second", formatCurrency(earnings.rates.perSecond, currency: currency, fractionDigits: 4))
                rate("Per minute", money(earnings.rates.perMinute))
                rate("Per hour", money(earnings.rates.perHour))
                rate("Per day", money(earnings.rates.perDay))
            } header: {
                Text("Your rate")
            } footer: {
                Text("Pay is spread evenly over each working day (Mon-Fri) between your start and end time.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func rate(_ label: String, _ amount: String) -> some View {
        LabeledContent(label) {
            Text(amount)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private func daysLeft(_ days: Int) -> String {
        switch days {
        case 0: "Today"
        case 1: "1 day"
        default: "\(days) days"
        }
    }
}
