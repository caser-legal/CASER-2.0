import SwiftUI

@MainActor
@Observable
final class AppRouter {
    enum AppTab: Int, Hashable, CaseIterable {
        case dashboard = 0
        case search = 1
        case monitor = 2
        case settings = 3
    }

    var selectedTab: AppTab = .dashboard
    var settingsPath: [SettingsView.Destination] = []
    var pendingMonitorMatchId: String?
    var pendingMonitorKeywordId: String?

    func openMonitor(matchId: String? = nil) {
        pendingMonitorMatchId = matchId
        selectedTab = .monitor
    }

    func openMonitor(keywordId: String) {
        pendingMonitorKeywordId = keywordId.isEmpty ? nil : keywordId
        selectedTab = .monitor
    }

    func openSearchFees() {
        selectedTab = .settings
        settingsPath = [.searchFees]
    }

    func openSaved() {
        selectedTab = .settings
        settingsPath = [.saved]
    }

    func openNotifications() {
        selectedTab = .settings
        settingsPath = [.notifications]
    }
}