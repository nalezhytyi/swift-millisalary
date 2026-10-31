import Foundation
import MillisalaryCore

extension Settings {
    /// The currency amounts are shown in. Until the exchange rate is ported
    /// that is the salary's own: showing `earningsCurrency` would put the
    /// wrong symbol on unconverted amounts
    var displayCurrency: String {
        monthlySalaryCurrency
    }

    /// What the window and the menu bar show for `date`
    func earnings(at date: Date, model: EarningsModel = EarningsModel()) -> EarningsSnapshot {
        model.earnings(at: date, earningsSettings(exchangeRate: 1))
    }
}
