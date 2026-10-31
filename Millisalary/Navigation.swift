import MillisalaryCore
import Observation
import SwiftUI

/// What the main window shows. Window state, not a setting; the period the
/// Earnings pane shows is the `selectedPeriod` setting
enum Pane: Hashable {
    case earnings, breakdown, settings
}

/// A row of the sidebar
enum SidebarItem: Hashable {
    case period(Period)
    case breakdown
    case settings

    /// Also the window's title while the row is selected
    var title: String {
        switch self {
        case .period(.hour): "This Hour"
        case .period(.day): "Today"
        case .period(.week): "This Week"
        case .period(.month): "This Month"
        case .period(.year): "This Year"
        case .breakdown: "Breakdown"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .period(.hour): "clock"
        case .period(.day): "sun.max"
        case .period(.week): "calendar.day.timeline.left"
        case .period(.month): "calendar"
        case .period(.year): "calendar.circle"
        case .breakdown: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

@Observable
final class Navigation {
    var pane = Pane.earnings
    var columnVisibility = NavigationSplitViewVisibility.all
    /// Set when the app was started at login: the window SwiftUI opens at
    /// launch closes again at once
    var hideOnLaunch = false

    func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }
}
