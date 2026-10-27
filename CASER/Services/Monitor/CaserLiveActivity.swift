@preconcurrency import ActivityKit
import Foundation
import UIKit
import os.log

private let liveActivityLogger = Logger(subsystem: "com.caser.app", category: "CaserLiveActivity")

@MainActor
enum CaserLiveActivity {
    static let maxActivities = 5
    private static let overdueAfter: TimeInterval = 2 * 60 * 60
    private static let progressInterval: TimeInterval = 1.5
    private static var lastProgressUpdate: [String: Date] = [:]
    private static var trailingProgressUpdates: Set<String> = []

    static func searchNow(keywordId: String) async {
        await MonitorScanService.shared.searchNow(keywordId: keywordId, timeBudget: 25)
    }

    static func sync() async {
        let wanted = wantedKeywords()
        let canStart = UIApplication.shared.applicationState != .background
        let wantedByID = Dictionary(wanted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var live: [String: Activity<CaserAlertAttributes>] = [:]
        for activity in Activity<CaserAlertAttributes>.activities {
            let id = activity.attributes.keywordId
            guard let keyword = wantedByID[id] else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            let isRunning = activity.activityState == .active || activity.activityState == .stale
            let isCurrent = activity.attributes.term == displayedTerm(for: keyword)
                && activity.attributes.scopeSummary == scopeSummary(for: keyword)
            if live[id] != nil {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else if isRunning && (isCurrent || !canStart) {
                live[id] = activity
            } else if canStart {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard !wanted.isEmpty else { return }

        let matches = MatchCacheStorage.shared.load()
        let stats = KeywordSearchStatsStorage.shared.load()
        let searches = MonitorScanService.shared.activeSearches
        for keyword in wanted {
            let content = makeContent(for: keyword, matches: matches, stats: stats[keyword.id], activeSearch: searches[keyword.id])
            if let activity = live[keyword.id] {
                await activity.update(
                    content,
                    alertConfiguration: newFilingAlert(for: keyword, from: activity.content.state, to: content.state)
                )
            } else if canStart {
                request(for: keyword, content: content)
            }
        }
    }

    static func update(keywordId: String) async {
        guard let keyword = KeywordMonitorStorage.shared.load().first(where: { $0.id == keywordId }) else { return }
        let activity = Activity<CaserAlertAttributes>.activities.first {
            $0.attributes.keywordId == keywordId && ($0.activityState == .active || $0.activityState == .stale)
        }
        guard let activity else {
            if UIApplication.shared.applicationState != .background { await sync() }
            return
        }
        let content = makeContent(
            for: keyword,
            matches: MatchCacheStorage.shared.load(),
            stats: KeywordSearchStatsStorage.shared.stats(for: keywordId),
            activeSearch: MonitorScanService.shared.activeSearches[keywordId]
        )
        await activity.update(
            content,
            alertConfiguration: newFilingAlert(for: keyword, from: activity.content.state, to: content.state)
        )
    }

    private static func newFilingAlert(
        for keyword: KeywordMonitor,
        from old: CaserAlertAttributes.ContentState,
        to new: CaserAlertAttributes.ContentState
    ) -> AlertConfiguration? {
        let hasNewFiling = new.newFilingCount > old.newFilingCount
            || (new.latestFilingAt ?? .distantPast) > (old.latestFilingAt ?? .distantPast)
        guard hasNewFiling, let title = new.latestFilingTitle else { return nil }
        let term = displayedTerm(for: keyword)
        return AlertConfiguration(
            title: LocalizedStringResource("New filing: \(term)"),
            body: LocalizedStringResource("\(title)"),
            sound: .default
        )
    }

    static func showProgress(keywordId: String) {
        let now = Date()
        if let last = lastProgressUpdate[keywordId], now.timeIntervalSince(last) < progressInterval {
            guard trailingProgressUpdates.insert(keywordId).inserted else { return }
            Task {
                try? await Task.sleep(for: .seconds(progressInterval))
                trailingProgressUpdates.remove(keywordId)
                lastProgressUpdate[keywordId] = Date()
                await update(keywordId: keywordId)
            }
            return
        }
        lastProgressUpdate[keywordId] = now
        Task { await update(keywordId: keywordId) }
    }

    static func endAll() async {
        for activity in Activity<CaserAlertAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func makeContent(
        for keyword: KeywordMonitor,
        matches: [CaseMatch],
        stats: KeywordSearchStats? = nil,
        activeSearch: CaserAlertAttributes.ActiveSearch? = nil,
        now: Date = Date()
    ) -> ActivityContent<CaserAlertAttributes.ContentState> {
        let keywordMatches = matches.filter { $0.keywordId == keyword.id }
        let filings = keywordMatches.filter {
            ($0.pubDate ?? $0.createdAt) >= keyword.monitoringStartedAt.addingTimeInterval(-120)
        }
        let latest = filings.max { ($0.pubDate ?? $0.createdAt) < ($1.pubDate ?? $1.createdAt) }
        let unread = keywordMatches.filter { !$0.read }.count
        let lastCheck = [keyword.lastCheckedAt, stats?.finishedAt].compactMap { $0 }.max()
        let next = MonitorScheduleService.nextScanDate(after: lastCheck ?? now)
        let showDetails = UserSettingsStore.shared.showNotificationDetails

        let state = CaserAlertAttributes.ContentState(
            lastCheckedAt: keyword.lastCheckedAt,
            newFilingCount: filings.count,
            latestFilingTitle: latest.map { showDetails ? String($0.title.prefix(160)) : "New filing" },
            latestFilingAt: latest.map { $0.pubDate ?? $0.createdAt },
            nextCheckAt: next,
            latestFilingCourt: showDetails ? latest?.courtName.map { String($0.prefix(60)) } : nil,
            unreadCount: unread,
            lastSearch: stats,
            activeSearch: activeSearch
        )

        let staleDate = activeSearch != nil
            ? now.addingTimeInterval(90)
            : max(lastCheck ?? now, now.addingTimeInterval(-overdueAfter)).addingTimeInterval(overdueAfter)
        var relevance: Double = activeSearch != nil ? 100 : (unread > 0 ? 50 + Double(min(unread, 40)) : 10)
        if keyword.isCritical { relevance += 5 }
        return ActivityContent(state: state, staleDate: staleDate, relevanceScore: relevance)
    }

    private static func wantedKeywords() -> [KeywordMonitor] {
        let settings = UserSettingsStore.shared
        guard settings.monitorAlertsEnabled, settings.liveActivitiesEnabled,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return [] }
        return Array(KeywordMonitorStorage.shared.load().filter {
            $0.isSearchable && $0.liveActivityEnabled
        }.prefix(maxActivities))
    }

    private static func request(for keyword: KeywordMonitor, content: ActivityContent<CaserAlertAttributes.ContentState>) {
        let attributes = CaserAlertAttributes(
            keywordId: keyword.id, term: displayedTerm(for: keyword),
            alertSetAt: keyword.monitoringStartedAt, scopeSummary: scopeSummary(for: keyword)
        )
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            liveActivityLogger.error("Could not start Live Activity: \(error)")
        }
    }

    private static func displayedTerm(for keyword: KeywordMonitor) -> String {
        UserSettingsStore.shared.showNotificationDetails ? keyword.term : "Case alert"
    }

    static func scopeSummary(for keyword: KeywordMonitor) -> String {
        if let courtID = keyword.scopedFeedId ?? keyword.scopedCourtId {
            return CourtFeedManager.shared.allFeeds.first { $0.id == courtID }?.name ?? "One court"
        }
        guard !keyword.selectedStates.isEmpty else { return "All courts" }
        let states = keyword.selectedStates.sorted()
        return states.count > 3 ? "\(states.prefix(3).joined(separator: ", ")) +\(states.count - 3)" : states.joined(separator: ", ")
    }
}
