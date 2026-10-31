import Foundation

private let ukrainian = Locale(identifier: "uk_UA")

/// An amount as the app shows it: the Ukrainian number format with the
/// narrow currency symbol after it and plain spaces, e.g. "54 321,00 ₴".
/// Halves round away from zero, as Intl.NumberFormat does (formatCurrency
/// in the Electron app)
public func formatCurrency(_ amount: Double, currency: String, fractionDigits: Int = 2) -> String {
    amount.formatted(
        .currency(code: currency)
            .locale(ukrainian)
            .presentation(.narrow)
            .precision(.fractionLength(fractionDigits))
            .rounded(rule: .toNearestOrAwayFromZero)
    )
    .replacingOccurrences(of: "\u{00A0}", with: " ")
}
