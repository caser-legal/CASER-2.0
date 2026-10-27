import Foundation
import UIKit
import UserNotifications
import os.log

private let monitorScanLogger = Logger(subsystem: "com.caser.app", category: "MonitorScanService")

extension KeywordMonitor {
    var isSearchable: Bool {
        enabled && !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
final class MonitorScanService {
    static let shared = MonitorScanService()

    private let rssService = LocalRSSService.shared
    private let feedManager = CourtFeedManager.shared
    private let keywordStorage = KeywordMonitorStorage.shared
    private let matchStorage = MatchCacheStorage.shared
    private let statsStorage = KeywordSearchStatsStorage.shared

    private var fullScan: Task<Int, Never>?
    private var keywordSearches: [String: Task<KeywordSearchStats?, Never>] = [:]
    private(set) var activeSearches: [String: CaserAlertAttributes.ActiveSearch] = [:]
    private(set) var didCompleteLastScan = false

    var isScanning: Bool { fullScan != nil }

    private static let maxCachedMatches = 500
    private static let maxNotificationGroups = 5
    private static let notificationWindow: TimeInterval = 24 * 60 * 60

    @discardableResult
    func scan(timeBudget: TimeInterval? = nil) async -> Int {
        if let fullScan { return await fullScan.value }
        let task = Task {
            NotificationCenter.default.post(name: .monitorScanStarted, object: nil)
            let found = await self.performFullScan(timeBudget: timeBudget)
            self.fullScan = nil
            NotificationCenter.default.post(name: .monitorScanCompleted, object: nil)
            return found
        }
        fullScan = task
        return await task.value
    }

    func cancelAll() {
        fullScan?.cancel()
        for search in keywordSearches.values { search.cancel() }
    }

    private func performFullScan(timeBudget: TimeInterval?) async -> Int {
        didCompleteLastScan = false

        let keywords: [KeywordMonitor]
        let feeds: [CourtFeed]
        do {
            keywords = try keywordStorage.loadVerified().filter(\.isSearchable)
            feeds = Self.feedsForScan(
                allFeeds: feedManager.feedsWithValidURLs, keywords: keywords,
                feedLimit: nil, checkedAt: try matchStorage.feedAttemptDates()
            )
        } catch {
            monitorScanLogger.error("Could not load alerts: \(error)")
            return 0
        }
        guard !keywords.isEmpty, !feeds.isEmpty else { return 0 }

        let backgroundTime = BackgroundTimeGuard(name: "CASER alert scan") { [weak self] in
            self?.cancelAll()
        }
        defer { backgroundTime.end() }

        monitorScanLogger.info("Scanning \(keywords.count) alerts across \(feeds.count) courts")
        let outcome = await runSearch(
            keywordIDs: Set(keywords.map(\.id)), feeds: feeds, timeBudget: timeBudget,
            maxConcurrent: timeBudget == nil ? 24 : 12, onDemand: false, onProgress: nil
        )
        didCompleteLastScan = outcome.reachedAnyCourt
        await CaserLiveActivity.sync()
        return outcome.newMatches
    }

    @discardableResult
    func searchNow(keywordId: String, timeBudget: TimeInterval? = 60) async -> KeywordSearchStats? {
        if let running = keywordSearches[keywordId] { return await running.value }
        let task = Task {
            let stats = await self.performKeywordSearch(keywordId: keywordId, timeBudget: timeBudget)
            self.keywordSearches[keywordId] = nil
            self.activeSearches[keywordId] = nil
            NotificationCenter.default.post(name: .monitorKeywordSearchDidChange, object: keywordId)
            await CaserLiveActivity.update(keywordId: keywordId)
            return stats
        }
        keywordSearches[keywordId] = task
        return await task.value
    }

    func isSearching(keywordId: String) -> Bool {
        keywordSearches[keywordId] != nil
    }

    private func performKeywordSearch(keywordId: String, timeBudget: TimeInterval?) async -> KeywordSearchStats? {
        guard let keyword = keywordStorage.load().first(where: { $0.id == keywordId }), keyword.isSearchable else {
            return nil
        }
        let feeds = Self.feedsForScan(allFeeds: feedManager.feedsWithValidURLs, keywords: [keyword], feedLimit: nil, checkedAt: [:])
        guard !feeds.isEmpty else { return nil }

        let backgroundTime = BackgroundTimeGuard(name: "CASER alert search") { [weak self] in
            self?.keywordSearches[keywordId]?.cancel()
        }
        defer { backgroundTime.end() }

        let startedAt = Date()
        activeSearches[keywordId] = CaserAlertAttributes.ActiveSearch(
            startedAt: startedAt, courtsSearched: 0, courtsTotal: feeds.count, filingsSearched: 0
        )
        NotificationCenter.default.post(name: .monitorKeywordSearchDidChange, object: keywordId)
        await CaserLiveActivity.update(keywordId: keywordId)

        let outcome = await runSearch(
            keywordIDs: [keywordId], feeds: feeds, timeBudget: timeBudget, maxConcurrent: 32, onDemand: true,
            onProgress: { scanned, total, entries, _ in
                Task { @MainActor in
                    self.reportProgress(keywordId: keywordId, startedAt: startedAt, scanned: scanned, total: total, filings: entries)
                }
            }
        )
        return outcome.stats[keywordId]
    }

    private func reportProgress(keywordId: String, startedAt: Date, scanned: Int, total: Int, filings: Int) {
        guard activeSearches[keywordId]?.startedAt == startedAt else { return }
        activeSearches[keywordId] = CaserAlertAttributes.ActiveSearch(
            startedAt: startedAt, courtsSearched: scanned, courtsTotal: total, filingsSearched: filings
        )
        NotificationCenter.default.post(name: .monitorKeywordSearchDidChange, object: keywordId)
        CaserLiveActivity.showProgress(keywordId: keywordId)
    }

    private struct SearchOutcome {
        var newMatches = 0
        var reachedAnyCourt = false
        var stats: [String: KeywordSearchStats] = [:]
    }

    private func runSearch(
        keywordIDs: Set<String>,
        feeds: [CourtFeed],
        timeBudget: TimeInterval?,
        maxConcurrent: Int,
        onDemand: Bool,
        onProgress: (@Sendable (Int, Int, Int, Int) -> Void)?
    ) async -> SearchOutcome {
        let fetch = await rssService.fetchFeedsWithResult(
            from: feeds, maxConcurrent: maxConcurrent, timeBudget: timeBudget, onProgress: onProgress
        )
        guard !fetch.wasCancelled else {
            monitorScanLogger.warning("Search cancelled before matching; nothing was recorded")
            return SearchOutcome()
        }

        let allKeywords: [KeywordMonitor]
        let existingKeys: Set<String>
        do {
            allKeywords = try keywordStorage.loadVerified()
            existingKeys = try matchStorage.processedKeys()
        } catch {
            monitorScanLogger.error("Could not load alert state: \(error)")
            return SearchOutcome()
        }
        let keywords = allKeywords.filter { keywordIDs.contains($0.id) && $0.isSearchable }
        guard !keywords.isEmpty else { return SearchOutcome() }

        let entries = fetch.entries
        let matchedAt = Date()
        let evaluation = await Task.detached(priority: .userInitiated) {
            MonitorMatchEngine.evaluate(keywords: keywords, entries: entries, existingKeys: existingKeys, now: matchedAt)
        }.value

        let completedAt = Date()
        let attempted = fetch.successfulFeedIDs.union(fetch.failedFeedIDs)
        let added: [CaseMatch]
        do {
            added = try matchStorage.mergeScan(
                newMatches: evaluation.matches,
                identityDates: evaluation.identityDates,
                keywords: allKeywords,
                successfulFeedIDs: fetch.successfulFeedIDs,
                attemptedFeedIDs: attempted,
                at: completedAt,
                isFullScan: !onDemand,
                trim: Self.trimToCap
            )
            try updateKeywordLastChecked(successfulFeedIDs: fetch.successfulFeedIDs)
        } catch {
            monitorScanLogger.error("Could not save search results: \(error)")
            return SearchOutcome()
        }

        let allFeeds = feedManager.feedsWithValidURLs
        let updates = keywords.compactMap { keyword -> KeywordSearchStatsStorage.Update? in
            let relevant = Self.relevantFeedIDs(for: keyword, in: allFeeds)
            guard !relevant.isDisjoint(with: attempted) else { return nil }
            return KeywordSearchStatsStorage.Update(
                keywordId: keyword.id,
                signature: keyword.matchSignature,
                relevantFeedIDs: relevant,
                successfulFeedIDs: fetch.successfulFeedIDs.intersection(relevant),
                failedFeedIDs: fetch.failedFeedIDs.intersection(relevant),
                byFeed: evaluation.counts[keyword.id]?.byFeed ?? [:],
                newMatches: added.lazy.filter { $0.keywordId == keyword.id }.count,
                finishedAt: completedAt,
                wasOnDemand: onDemand
            )
        }
        let existingKeywordIds = Set(allKeywords.map(\.id))
        let stats = statsStorage.apply(updates, existingKeywordIds: existingKeywordIds)
        let matchingEntries = evaluation.matchingEntries
        let resultUpdates = updates.map { update in
            AlertResultsStorage.Update(
                keywordId: update.keywordId,
                signature: update.signature,
                relevantFeedIDs: update.relevantFeedIDs,
                successfulFeedIDs: update.successfulFeedIDs,
                byFeed: matchingEntries[update.keywordId] ?? [:]
            )
        }
        await Task.detached(priority: .utility) {
            AlertResultsStorage.shared.apply(resultUpdates, existingKeywordIds: existingKeywordIds)
        }.value

        monitorScanLogger.info("Search finished: \(fetch.successfulFeedIDs.count) courts read, \(fetch.failedFeedIDs.count) unavailable, \(added.count) new matches")
        if !added.isEmpty {
            await SavingsTrackerStore.shared.trackLiveScan(
                billableResults: added.count,
                billablePages: SearchFees.billablePagesForSearchRequests(added.count)
            )
        }

        await deliverNotifications(now: completedAt)
        await syncUnreadBadge()
        return SearchOutcome(newMatches: added.count, reachedAnyCourt: !fetch.successfulFeedIDs.isEmpty, stats: stats)
    }

    private func updateKeywordLastChecked(successfulFeedIDs: Set<String>) throws {
        var keywords = try keywordStorage.loadVerified()
        let attemptedAt = try matchStorage.feedAttemptDates()
        let feeds = feedManager.feedsWithValidURLs
        var changed = false
        for index in keywords.indices where keywords[index].enabled {
            let required = Self.relevantFeedIDs(for: keywords[index], in: feeds)
            guard !required.isEmpty, !required.isDisjoint(with: successfulFeedIDs) else { continue }
            let dates = required.compactMap { attemptedAt[$0] }
            guard dates.count == required.count, let oldest = dates.min(),
                  oldest > (keywords[index].lastCheckedAt ?? .distantPast) else { continue }
            keywords[index].lastCheckedAt = oldest
            changed = true
        }
        if changed { try keywordStorage.save(keywords) }
    }

    static func feedsForScan(
        allFeeds: [CourtFeed], keywords: [KeywordMonitor], feedLimit: Int?, checkedAt: [String: Date]
    ) -> [CourtFeed] {
        let relevant = allFeeds.filter { feed in
            keywords.contains { $0.enabled && $0.covers(feed) }
        }.sorted { lhs, rhs in
            let left = checkedAt[lhs.id] ?? .distantPast
            let right = checkedAt[rhs.id] ?? .distantPast
            return left == right ? lhs.id < rhs.id : left < right
        }
        guard let feedLimit, feedLimit > 0 else { return relevant }
        return Array(relevant.prefix(feedLimit))
    }

    static func relevantFeedIDs(for keyword: KeywordMonitor, in feeds: [CourtFeed]) -> Set<String> {
        Set(feeds.filter { keyword.covers($0) }.map(\.id))
    }

    static func trimToCap(_ matches: [CaseMatch]) -> [CaseMatch] {
        guard matches.count > maxCachedMatches else { return matches }
        let retained = matches.filter { !$0.notified || $0.starred }
        let retainedIDs = Set(retained.map(\.id))
        let others = matches.filter { !retainedIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
        return retained + others.prefix(max(0, maxCachedMatches - retained.count))
    }

    private func deliverNotifications(now: Date) async {
        let pending = matchStorage.load().filter { !$0.notified }
        guard !pending.isEmpty else { return }

        var keywordByID: [String: KeywordMonitor] = [:]
        for keyword in keywordStorage.load() {
            keywordByID[keyword.id] = keyword
        }
        let alertsOn = UserSettingsStore.shared.monitorAlertsEnabled

        var handled = Set<String>()
        var announce: [CaseMatch] = []
        for match in pending {
            if alertsOn,
               let keyword = match.keywordId.flatMap({ keywordByID[$0] }),
               keyword.enabled, keyword.notifyPush,
               now.timeIntervalSince(match.createdAt) < Self.notificationWindow {
                announce.append(match)
            } else {
                handled.insert(match.id)
            }
        }

        if !announce.isEmpty {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                handled.formUnion(await post(announce, keywordByID: keywordByID))
            default:
                monitorScanLogger.info("Notifications not allowed; \(announce.count) matches will be announced if allowed within 24 hours")
            }
        }
        matchStorage.markNotified(handled)
    }

    private func post(_ matches: [CaseMatch], keywordByID: [String: KeywordMonitor]) async -> Set<String> {
        let center = UNUserNotificationCenter.current()
        let showDetails = UserSettingsStore.shared.showNotificationDetails
        let unread = matchStorage.load().filter { !$0.read }.count
        let existing = Set(await center.pendingNotificationRequests().map(\.identifier))
            .union(await center.deliveredNotifications().map(\.request.identifier))

        let groups = Dictionary(grouping: matches) { $0.keywordId ?? $0.keyword }.values
            .map { $0.sorted { ($0.pubDate ?? $0.createdAt) > ($1.pubDate ?? $1.createdAt) } }
            .sorted { ($0[0].pubDate ?? $0[0].createdAt) > ($1[0].pubDate ?? $1[0].createdAt) }

        var requests: [(request: UNNotificationRequest, matches: [CaseMatch])] = []
        if groups.count > Self.maxNotificationGroups {
            let content = MonitorNotificationContent.summary(
                matches: matches, alertTerms: groups.map { $0[0].keyword }, showDetails: showDetails, badge: unread
            )
            requests.append((UNNotificationRequest(identifier: "monitor-summary-\(groups[0][0].id)", content: content, trigger: nil), matches))
        } else {
            for group in groups {
                let keyword = group[0].keywordId.flatMap { keywordByID[$0] }
                let content = MonitorNotificationContent.alert(
                    matches: group, keyword: keyword, showDetails: showDetails, badge: unread
                )
                requests.append((UNNotificationRequest(identifier: "monitor-\(group[0].id)", content: content, trigger: nil), group))
            }
        }

        var announced = Set<String>()
        var delivered: [(matchID: String, alertTerm: String)] = []
        var failed: [(matchID: String, alertTerm: String)] = []
        for (request, group) in requests {
            do {
                if !existing.contains(request.identifier) {
                    try await center.add(request)
                }
                announced.formUnion(group.map(\.id))
                delivered += group.map { ($0.id, $0.keyword) }
            } catch {
                failed += group.map { ($0.id, $0.keyword) }
                monitorScanLogger.error("Could not add notification: \(error)")
            }
        }
        MonitorDeliveryHistory.shared.record(delivered, state: .delivered)
        MonitorDeliveryHistory.shared.record(failed, state: .failed)
        return announced
    }

    private func syncUnreadBadge() async {
        let totalUnread = matchStorage.load().filter { !$0.read }.count
        await NotificationManager.shared.setMonitorBadgeCount(totalUnread)
    }
}

@MainActor
final class BackgroundTimeGuard {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String, onExpire: @escaping @MainActor @Sendable () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            onExpire()
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
