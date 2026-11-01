import Foundation

/// What the menu bar item shows (tray.ts in the Electron app): the amount
/// next to the icon and the menu's rows of period amounts
public struct MenuBarContent: Equatable, Sendable {
    /// Today's or the selected period's earnings; empty before a salary is
    /// set, so the icon alone says the app is there
    public var title: String
    /// "This hour: 1,23 ₴" and so on up to the year; none without a salary
    public var rows: [String]

    /// `earnings` is nil when there is no salary to earn from; the rows are
    /// in `locale`'s language, or the app's when nil
    public init(settings: Settings, earnings: EarningsSnapshot?, currency: String, locale: Locale? = nil) {
        guard let earnings else {
            title = ""
            rows = []
            return
        }

        let period = settings.menuBarAmount == .selected ? settings.selectedPeriod : .day
        title = formatCurrency(earnings[period].earned, currency: currency)
        rows = Period.allCases.map {
            "\($0.label(in: locale)): \(formatCurrency(earnings[$0].earned, currency: currency))"
        }
    }
}
