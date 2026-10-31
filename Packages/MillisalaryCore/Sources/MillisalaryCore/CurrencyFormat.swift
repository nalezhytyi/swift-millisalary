import Foundation

private let ukrainian = Locale(identifier: "uk_UA")

/// An amount as the app shows it: the Ukrainian number format with the
/// narrow currency symbol after it and plain spaces, e.g. "54 321,00 ₴".
/// Halves round away from zero, as Intl.NumberFormat does (formatCurrency
/// in the Electron app)
public func formatCurrency(_ amount: Double, currency: String, fractionDigits: Int = 2) -> String {
    amount.formatted(currencyStyle(currency, fractionDigits: fractionDigits))
        .replacingOccurrences(of: "\u{00A0}", with: " ")
}

/// The pieces of a formatted amount, for laying them out separately (the
/// dial shows the last fraction digits smaller and the symbol in colour)
public struct CurrencyParts: Equatable, Sendable {
    public enum SymbolPosition: String, Sendable {
        case prefix, suffix
    }

    /// Narrow currency symbol, e.g. "$", "₴" or "zł"
    public var symbol: String
    public var symbolPosition: SymbolPosition
    public var sign: String
    /// Whole part with group separators
    public var integer: String
    public var decimal: String
    public var fraction: String
}

/// formatCurrency split into its parts (formatCurrencyParts)
public func formatCurrencyParts(_ amount: Double, currency: String, fractionDigits: Int = 2) -> CurrencyParts {
    let formatted = amount.formatted(currencyStyle(currency, fractionDigits: fractionDigits).attributed)
    var parts = CurrencyParts(symbol: "", symbolPosition: .suffix, sign: "", integer: "", decimal: "", fraction: "")
    var seenInteger = false

    for run in formatted.runs {
        let text = String(formatted[run.range].characters)
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        switch (run.numberSymbol, run.numberPart) {
        case (.currency?, _):
            parts.symbol += text
            if !seenInteger { parts.symbolPosition = .prefix }
        case (.sign?, _):
            parts.sign += text
        case (.decimalSeparator?, _):
            parts.decimal += text
        case (.groupingSeparator?, _), (_, .integer?):
            parts.integer += text
            seenInteger = true
        case (_, .fraction?):
            parts.fraction += text
        default:
            // The space between the number and the symbol
            break
        }
    }

    return parts
}

private func currencyStyle(_ currency: String, fractionDigits: Int) -> FloatingPointFormatStyle<Double>.Currency {
    .currency(code: currency)
        .locale(ukrainian)
        .presentation(.narrow)
        .precision(.fractionLength(fractionDigits))
        .rounded(rule: .toNearestOrAwayFromZero)
}
