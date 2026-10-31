import MillisalaryCore
import SwiftUI

/// The main window's content: the sidebar, and the selected period, the
/// Breakdown or the Settings next to it
struct MainView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(Navigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation

        NavigationSplitView(columnVisibility: $navigation.columnVisibility) {
            SidebarView(selection: selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
        } detail: {
            detail
                .navigationTitle(selected.title)
        }
        .frame(minWidth: 520, minHeight: 460)
        .background(TickWhileVisible())
    }

    private var selected: SidebarItem {
        switch navigation.pane {
        case .earnings: .period(store.settings.selectedPeriod)
        case .breakdown: .breakdown
        case .settings: .settings
        }
    }

    /// Picking a period selects it in the settings too, as the Electron app
    /// does; Breakdown and Settings are only window state
    private var selection: Binding<SidebarItem?> {
        Binding {
            selected
        } set: { item in
            switch item {
            case .period(let period):
                store.update { $0.selectedPeriod = period }
                navigation.pane = .earnings
            case .breakdown:
                navigation.pane = .breakdown
            case .settings:
                navigation.pane = .settings
            case nil:
                break
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch navigation.pane {
        case .earnings: EarningsView()
        case .breakdown: BreakdownView()
        case .settings: SettingsView()
        }
    }
}

private struct SidebarView: View {
    let selection: Binding<SidebarItem?>

    var body: some View {
        List(selection: selection) {
            Section("Earnings") {
                ForEach(Period.allCases, id: \.self) { period in
                    row(.period(period))
                }
            }
            Section {
                row(.breakdown)
                row(.settings)
            }
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .tag(item)
    }
}
