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

extension SidebarItem {
    var pane: Pane {
        switch self {
        case .period: .earnings
        case .breakdown: .breakdown
        case .settings: .settings
        }
    }

    /// The analytics `item`: a period's name, "breakdown" or "settings"
    var analyticsName: String {
        switch self {
        case .period(let period): period.rawValue
        case .breakdown: "breakdown"
        case .settings: "settings"
        }
    }
}

/// Where a selection or a toggle came from, as the Electron app reported it
enum ActionSource: String {
    case sidebar, shortcut, tray, menu, button
    case setupHint = "setup_hint"
}

@Observable
final class Navigation {
    var pane = Pane.earnings
    var columnVisibility = NavigationSplitViewVisibility.all
    /// Set when the app was started at login: the window SwiftUI opens at
    /// launch closes again at once
    var hideOnLaunch = false
    /// The next sidebar toggle's source; SwiftUI's own button (and dragging
    /// the sidebar shut) change `columnVisibility` without saying so
    @ObservationIgnored private var toggleSource: ActionSource?

    func toggleSidebar(source: ActionSource) {
        toggleSource = source
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }

    /// The source of the toggle that just happened
    func takeToggleSource() -> ActionSource {
        defer { toggleSource = nil }
        return toggleSource ?? .button
    }

    func selected(in settings: MillisalaryCore.Settings) -> SidebarItem {
        switch pane {
        case .earnings: .period(settings.selectedPeriod)
        case .breakdown: .breakdown
        case .settings: .settings
        }
    }

    /// Selects a row of the sidebar (select in the Electron app's
    /// useAppState): a period is also the `selectedPeriod` setting.
    /// period_changed and sidebar_item_selected go out only for a change;
    /// the View menu's periods report the first from `menu` and the second
    /// from `shortcut`, as the Electron app did
    func select(
        _ item: SidebarItem,
        source: ActionSource,
        periodSource: ActionSource? = nil,
        store: SettingsStore,
        analytics: Analytics
    ) {
        let previous = selected(in: store.settings)

        if case .period(let period) = item, period != store.settings.selectedPeriod {
            store.update { $0.selectedPeriod = period }
            analytics.track("period_changed", [
                "period": .string(period.rawValue),
                "source": .string((periodSource ?? source).rawValue),
            ])
        }
        pane = item.pane
        if item != previous {
            analytics.track("sidebar_item_selected", ["item": .string(item.analyticsName), "source": .string(source.rawValue)])
        }
    }
}
