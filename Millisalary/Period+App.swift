import MillisalaryCore

extension Period {
    /// What a period's amount is for: "today" after "of 1 000 ₴" and in
    /// "Left today"
    var caption: String {
        switch self {
        case .hour: String(localized: "this hour")
        case .day: String(localized: "today")
        case .week: String(localized: "this week")
        case .month: String(localized: "this month")
        case .year: String(localized: "this year")
        }
    }

    /// The dial's: an hour's amount is said to be per hour, the others'
    /// are the period's
    var dialCaption: String {
        self == .hour ? String(localized: "per hour") : caption
    }
}
