/// What the menu bar item shows (tray.ts in the Electron app): the amount
/// next to the icon and the menu's rows of period amounts
public struct MenuBarContent: Equatable, Sendable {
    /// Today's or the selected period's earnings; empty before a salary is
    /// set, so the icon alone says the app is there
    public var title: String
    /// "This hour: 1,23 ₴" and so on up to the year; none without a salary
    public var rows: [String]

    /// `earnings` is nil when there is no salary to earn from
    public init(settings: Settings, earnings: EarningsSnapshot?, currency: String) {
        guard let earnings else {
            title = ""
            rows = []
            return
        }

        let period = settings.menuBarAmount == .selected ? settings.selectedPeriod : .day
        title = formatCurrency(earnings[period].earned, currency: currency)
        rows = Period.allCases.map {
            "\(Self.label(for: $0)): \(formatCurrency(earnings[$0].earned, currency: currency))"
        }
    }

    static func label(for period: Period) -> String {
        switch period {
        case .hour: "This hour"
        case .day: "Today"
        case .week: "This week"
        case .month: "This month"
        case .year: "This year"
        }
    }
}
