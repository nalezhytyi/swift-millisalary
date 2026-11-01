import AppKit
import MillisalaryCore
import SwiftUI

/// The monthly salary's field, in Settings and in the setup form: bordered
/// and right-aligned, taking only what a number can have, as a number
/// field's formatter does. An edit that adds anything else (a minus, a
/// letter) is undone with a beep, and "." or "," becomes the locale's
/// decimal separator (salaryInput)
struct SalaryField: View {
    @Binding var text: String
    let focus: FocusState<Bool>.Binding
    /// Text put in from outside that the filter lets be: the stored salary,
    /// shown again after a commit
    var stored: String?

    var body: some View {
        TextField("Monthly salary", text: $text, prompt: Text(0, format: .number.precision(.fractionLength(2))))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 150)
            .focused(focus)
            .onChange(of: text) { old, new in
                guard new != stored else { return }
                if let input = salaryInput(new) {
                    if input != new { text = input }
                } else {
                    NSSound.beep()
                    text = old
                }
            }
    }
}

/// A currency pop-up's choices, the current one included when it isn't
/// one of them
struct CurrencyOptions: View {
    let current: String

    private static let currencies = ["UAH", "USD", "EUR", "PLN", "CZK", "RON"]

    var body: some View {
        ForEach(Self.currencies.including(current), id: \.self) { currency in
            Text(currency).tag(currency)
        }
    }
}

extension Array where Element: Comparable {
    /// The choices plus `current` when it isn't one of them, in order (hours
    /// a day follow Start and End, so 09:00-17:20 makes 8.33)
    func including(_ current: Element) -> [Element] {
        contains(current) ? self : (self + [current]).sorted()
    }
}
