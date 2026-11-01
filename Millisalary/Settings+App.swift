import AppKit
import MillisalaryCore

/// How amounts are shown: converted to the display currency once the rate
/// for the pair is known, and until then in the salary's own currency. (The
/// Electron app multiplied by 1 and showed the display currency's symbol
/// while it waited, which put wrong numbers on screen)
struct AmountDisplay: Equatable {
    let currency: String
    let exchangeRate: Double

    /// The rate in use for `pair` as shown ("45,4"): nil with one currency,
    /// or while the amounts wait in the salary's currency for it
    func rate(for pair: CurrencyPair) -> String? {
        guard !pair.isSameCurrency, currency == pair.to else { return nil }
        return exchangeRate.formatted(.number.precision(.fractionLength(0...4)))
    }
}

/// What a salary field keeps of an edit: only what a number can have, as a
/// number field's formatter does. An edit that adds anything else (a minus,
/// a letter) is undone with a beep, and "." or "," becomes the locale's
/// decimal separator (salaryInput). Returns the text the field should show
/// instead, or nil to keep the edit
func salaryFieldText(after old: String, _ text: String) -> String? {
    if let input = salaryInput(text) {
        return input == text ? nil : input
    }
    NSSound.beep()
    return old
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

    /// The times the earnings use when one is cleared: 09:00, and Start plus
    /// hours a day
    var startTime: TimeOfDay {
        TimeOfDay(parsing: startHour) ?? TimeOfDay(hour: 9, minute: 0)
    }

    var endTime: TimeOfDay {
        TimeOfDay(parsing: endHour)
            ?? MillisalaryCore.endHour(from: startTime, workingHoursPerDay: workingHoursPerDay)
    }
}

extension TimeOfDay {
    // DatePicker edits a Date: a fixed day carries the time, one without a
    // DST change so every time of day exists on it
    private static let pickerDay = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))

    /// This time on the day a DatePicker edits
    var pickerDate: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Self.pickerDay)!
    }

    init(pickerDate date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}
