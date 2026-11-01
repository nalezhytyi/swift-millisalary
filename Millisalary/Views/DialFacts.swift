import MillisalaryCore
import SwiftUI

extension DialFact {
    /// Its name in Settings' list
    var title: String {
        switch self {
        case .perSecond: "Per second"
        case .perMinute: "Per minute"
        case .perHour: "Per hour"
        case .perDay: "Per day"
        case .nextPayday: "Next payday"
        case .paycheck: "Paycheck"
        case .leftToEarn: "Left to earn"
        case .earnedToday: "Earned today"
        case .exchangeRate: "Exchange rate"
        }
    }
}

/// What each fact under the dial says right now
struct DialFactFigures {
    let earnings: EarningsSnapshot
    let period: Period
    let currency: String
    let pair: CurrencyPair
    /// "45,4"; nil with one currency, or until the rate arrives
    let rate: String?

    init(_ settings: MillisalaryCore.Settings, _ display: AmountDisplay, _ earnings: EarningsSnapshot) {
        self.earnings = earnings
        period = settings.selectedPeriod
        currency = display.currency
        pair = settings.ratePair
        rate = display.rate(for: pair)
    }

    /// "today", "this week", …: what's left is the selected period's
    var caption: String {
        switch period {
        case .hour: "this hour"
        case .day: "today"
        case .week: "this week"
        case .month: "this month"
        case .year: "this year"
        }
    }

    /// Under the figure in the card: the fact's name, the period's for what's
    /// left, and the rate's as "Per 1 USD" under "45,4 UAH", which fits a
    /// quarter of the card
    func label(_ fact: DialFact) -> String {
        switch fact {
        case .leftToEarn: "Left \(caption)"
        case .exchangeRate where rate != nil: "Per 1 \(pair.from)"
        default: fact.title
        }
    }

    /// Beside the checkbox in Settings, where there's room to say it all
    func sample(_ fact: DialFact) -> Text {
        switch fact {
        case .leftToEarn: Text("\(value(fact)) \(caption)")
        case .exchangeRate: Text(rate.map { "1 \(pair.from) = \($0) \(pair.to)" } ?? "—")
        default: value(fact)
        }
    }

    /// `compact` leaves the payday's date out, for a quarter of the card
    func value(_ fact: DialFact, compact: Bool = false) -> Text {
        let rates = earnings.rates
        switch fact {
        case .perSecond: return Text(formatCurrency(rates.perSecond, currency: currency, fractionDigits: 4))
        case .perMinute: return money(rates.perMinute)
        case .perHour: return money(rates.perHour)
        case .perDay: return money(rates.perDay)
        case .nextPayday: return payday(withDate: !compact)
        case .paycheck: return money(earnings.nextPayday.amount)
        case .leftToEarn: return money(max(0, earnings[period].total - earnings[period].earned))
        case .earnedToday: return money(earnings.day.earned)
        case .exchangeRate: return Text(rate.map { "\($0) \(pair.to)" } ?? "—")
        }
    }

    private func money(_ amount: Double) -> Text {
        Text(formatCurrency(amount, currency: currency))
    }

    /// "In 6 days · Tue, 10 Nov", "Tomorrow · …" or "Today"
    private func payday(withDate: Bool) -> Text {
        let next = earnings.nextPayday
        let when: String = switch next.daysLeft {
        case 0: "Today"
        case 1: "Tomorrow"
        default: "In \(next.daysLeft) days"
        }
        guard withDate, next.daysLeft > 0 else { return Text(when) }
        let date = Text(next.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .font(.callout.weight(.regular))
            .foregroundStyle(.secondary)
        return Text("\(when) \(Text("· ").font(.callout).foregroundStyle(.secondary))\(date)")
    }
}

/// The chosen facts side by side, split by dividers: the card under the
/// dial, and its preview in Settings
struct DialFactCells: View {
    let facts: [DialFact]
    let figures: DialFactFigures

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(facts.enumerated()), id: \.element) { index, fact in
                if index > 0 {
                    Divider()
                }
                FigureCell(value: figures.value(fact, compact: facts.count >= DialFact.maximum), label: figures.label(fact))
            }
        }
        .padding(.vertical, 4)
    }
}
