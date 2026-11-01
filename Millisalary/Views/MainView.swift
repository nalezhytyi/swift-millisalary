import MillisalaryCore
import SwiftUI

/// The main window's content: the sidebar, and the selected period or the
/// Breakdown next to it
struct MainView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(Navigation.self) private var navigation
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(FrameAnimation.self) private var face
    @Environment(SplashModel.self) private var splash
    @Environment(Analytics.self) private var analytics

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
        .background(TitlebarHider(hidden: splash.hidesToolbar))
        .overlay {
            if splash.isVisible {
                SplashView()
            }
        }
        .onAppear {
            // The face's frames live as long as the window
            face.load()
            // Started at login: the menu bar item only, until asked
            if navigation.hideOnLaunch {
                navigation.hideOnLaunch = false
                dismissWindow(id: AppController.mainWindowID)
            }
        }
        .onDisappear { face.unload() }
        .onChange(of: navigation.columnVisibility) { _, visibility in
            analytics.track("sidebar_toggled", [
                "visible": .bool(visibility != .detailOnly),
                "source": .string(navigation.takeToggleSource(for: visibility).rawValue),
            ])
        }
    }

    private var selected: SidebarItem {
        navigation.selected(in: store.settings)
    }

    /// Picking a period selects it in the settings too, as the Electron app
    /// does; Breakdown is only window state
    private var selection: Binding<SidebarItem?> {
        Binding {
            selected
        } set: { item in
            if let item {
                navigation.select(item, source: .sidebar, store: store, analytics: analytics)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch navigation.pane {
        case .earnings: EarningsView()
        case .breakdown: BreakdownView()
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
            }
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .tag(item)
    }
}
