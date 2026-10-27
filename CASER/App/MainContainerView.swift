import SwiftUI

struct MainContainerView: View {
    @Environment(AppRouter.self) private var router
    @Environment(UserSettingsStore.self) private var userSettings
    @State private var dashboardPath: [DashboardView.Destination] = []
    @State private var settingsResetID = 0

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            DashboardView(path: $dashboardPath)
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }
                .toolbar(.visible, for: .tabBar)
                .tag(AppRouter.AppTab.dashboard)

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .toolbar(.visible, for: .tabBar)
                .tag(AppRouter.AppTab.search)

            MonitorView()
                .tabItem {
                    Label("Alerts", systemImage: "bell.badge")
                }
                .toolbar(.visible, for: .tabBar)
                .tag(AppRouter.AppTab.monitor)
                .monitorBadge(count: userSettings.monitorBadgeCount)

            SettingsView(path: $router.settingsPath)
                .id(settingsResetID)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .toolbar(.visible, for: .tabBar)
                .tag(AppRouter.AppTab.settings)
        }
        .tint(Color.caserAccent)
        .onChange(of: router.selectedTab) { oldTab, newTab in
            if oldTab == .settings, newTab != .settings {
                router.settingsPath.removeAll()
                settingsResetID += 1
            }

            if !UIAccessibility.isVoiceOverRunning && !UIAccessibility.isReduceMotionEnabled {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSearchFees)) { _ in
            router.openSearchFees()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSaved)) { _ in
            router.openSaved()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNotifications)) { _ in
            router.openNotifications()
        }
    }
}

private struct MonitorBadgeModifier: ViewModifier {
    let count: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if count > 0 {
            content.badge(count)
        } else {
            content
        }
    }
}

private extension View {
    func monitorBadge(count: Int) -> some View {
        modifier(MonitorBadgeModifier(count: count))
    }
}
