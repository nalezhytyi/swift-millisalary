import Foundation
import MillisalaryCore

/// How amounts are shown: converted to the display currency once the rate
/// for the pair is known, and until then in the salary's own currency. (The
/// Electron app multiplied by 1 and showed the display currency's symbol
/// while it waited, which put wrong numbers on screen)
struct AmountDisplay: Equatable {
    let currency: String
    let exchangeRate: Double
}

extension Settings {
    func amountDisplay(_ rates: ExchangeRateStore) -> AmountDisplay {
        if let rate = rates.rate(for: ratePair) {
            AmountDisplay(currency: earningsCurrency, exchangeRate: rate)
        } else {
            AmountDisplay(currency: monthlySalaryCurrency, exchangeRate: 1)
        }
    }

    /// What the window and the menu bar show for `date`
    func earnings(at date: Date, _ display: AmountDisplay, model: EarningsModel = EarningsModel()) -> EarningsSnapshot {
        model.earnings(at: date, earningsSettings(exchangeRate: display.exchangeRate))
    }
}
