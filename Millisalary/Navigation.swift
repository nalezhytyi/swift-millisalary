import MillisalaryCore
import Observation
import SwiftUI

/// What the main window shows. Window state, not a setting; the period the
/// Earnings pane shows is the `selectedPeriod` setting. Settings is a window
/// of its own
enum Pane: Hashable {
    case earnings, breakdown
}

/// A tab of the Settings window. Window state too
enum SettingsTab: String, Hashable {
    case general, pay, schedule, glance, notifications
}

/// A row of the sidebar
enum SidebarItem: Hashable {
    case period(Period)
    case breakdown

    /// Also the window's title while the row is selected
    var title: String {
        switch self {
        case .period(.hour): String(localized: "This Hour")
        case .period(.day): String(localized: "Today")
        case .period(.week): String(localized: "This Week")
        case .period(.month): String(localized: "This Month")
        case .period(.year): String(localized: "This Year")
        case .breakdown: String(localized: "Breakdown")
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
        }
    }
}

extension SidebarItem {
    /// The row that shows `pane`: for Earnings, the row of `period`
    init(_ pane: Pane, period: Period) {
        self = switch pane {
        case .earnings: .period(period)
        case .breakdown: .breakdown
        }
    }

    var pane: Pane {
        switch self {
        case .period: .earnings
        case .breakdown: .breakdown
        }
    }

    /// The analytics `item`: a period's name or "breakdown"
    var analyticsName: String {
        switch self {
        case .period(let period): period.rawValue
        case .breakdown: "breakdown"
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
    var settingsTab = SettingsTab.general
    var columnVisibility = NavigationSplitViewVisibility.all
    /// Set when the app was started at login: the window SwiftUI opens at
    /// launch closes again at once
    var hideOnLaunch = false
    /// The setup form's fields while they hold a salary that would start
    /// earning. Settings stores them when its window comes to the front
    /// (SalarySetupView.save), so what was typed there isn't left behind
    /// for Settings' stored 0
    var setupDraft: MillisalaryCore.Settings?
    /// The last `toggleSidebar`'s source and the visibility it set. SwiftUI's
    /// own button (and dragging the sidebar shut) change `columnVisibility`
    /// without saying so. A toggle made while the window is closed (⌃⌘S)
    /// may never reach the window's `onChange`, so a change is only the
    /// toggle's when it lands on the visibility the toggle set
    @ObservationIgnored private var lastToggle: (source: ActionSource, visibility: NavigationSplitViewVisibility)?

    func toggleSidebar(source: ActionSource) {
        let visibility: NavigationSplitViewVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        lastToggle = (source, visibility)
        columnVisibility = visibility
    }

    /// The source of the change to `visibility` that just happened: the
    /// last toggle's when it set that visibility, otherwise the button's
    func takeToggleSource(for visibility: NavigationSplitViewVisibility) -> ActionSource {
        defer { lastToggle = nil }
        guard let lastToggle, lastToggle.visibility == visibility else { return .button }
        return lastToggle.source
    }

    func selected(in settings: MillisalaryCore.Settings) -> SidebarItem {
        SidebarItem(pane, period: settings.selectedPeriod)
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
