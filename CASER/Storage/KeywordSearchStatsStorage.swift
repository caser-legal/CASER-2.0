import Foundation
import os.log

private let statsLogger = Logger(subsystem: "com.caser.app", category: "KeywordSearchStats")

typealias KeywordSearchStats = CaserAlertAttributes.LastSearch

struct KeywordSearchStatsStorage: Sendable {
    static let shared = KeywordSearchStatsStorage()

    struct Update: Sendable {
        let keywordId: String
        let signature: String
        let relevantFeedIDs: Set<String>
        let successfulFeedIDs: Set<String>
        let failedFeedIDs: Set<String>
        let byFeed: [String: FeedTally]
        let newMatches: Int
        let finishedAt: Date
        let wasOnDemand: Bool
    }

    private struct Record: Codable {
        var summary: KeywordSearchStats
        var signature: String
        var feeds: [String: FeedTally]
        var failedFeeds: Set<String>
    }

    private let filename = "monitor_keyword_search_stats.json"
    private let storage: any MonitorFileStorage

    init(storage: any MonitorFileStorage = SecureFileStore(protection: .completeUntilFirstUserAuthentication)) {
        self.storage = storage
    }

    func load() -> [String: KeywordSearchStats] {
        loadRecords().mapValues(\.summary)
    }

    func stats(for keywordId: String) -> KeywordSearchStats? {
        loadRecords()[keywordId]?.summary
    }

    @discardableResult
    func apply(_ updates: [Update], existingKeywordIds: Set<String>) -> [String: KeywordSearchStats] {
        var records = loadRecords().filter { existingKeywordIds.contains($0.key) }
        var summaries: [String: KeywordSearchStats] = [:]
        for update in updates where existingKeywordIds.contains(update.keywordId) {
            let previous = records[update.keywordId].flatMap { $0.signature == update.signature ? $0 : nil }
            let relevant = update.relevantFeedIDs
            var feeds = (previous?.feeds ?? [:]).filter { relevant.contains($0.key) }
            var failed = (previous?.failedFeeds ?? []).intersection(relevant)
            for id in update.successfulFeedIDs where relevant.contains(id) {
                feeds[id] = update.byFeed[id] ?? FeedTally()
                failed.remove(id)
            }
            for id in update.failedFeedIDs where relevant.contains(id) {
                failed.insert(id)
            }
            let summary = KeywordSearchStats(
                finishedAt: update.finishedAt,
                matchingFilings: feeds.values.reduce(0) { $0 + $1.matching },
                filingsSearched: feeds.values.reduce(0) { $0 + $1.filings },
                newMatches: update.newMatches,
                courtsSearched: feeds.count,
                courtsTotal: relevant.count,
                courtsFailed: failed.count,
                wasOnDemand: update.wasOnDemand
            )
            records[update.keywordId] = Record(summary: summary, signature: update.signature, feeds: feeds, failedFeeds: failed)
            summaries[update.keywordId] = summary
        }
        save(records)
        return summaries
    }

    func remove(keywordId: String) {
        var records = loadRecords()
        guard records.removeValue(forKey: keywordId) != nil else { return }
        save(records)
    }

    func clear() {
        do { try storage.delete(filename) }
        catch { statsLogger.error("Could not clear search stats: \(error)") }
    }

    private func loadRecords() -> [String: Record] {
        guard storage.exists(filename) else { return [:] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode([String: Record].self, from: storage.load(from: filename))
        } catch {
            statsLogger.error("Could not load search stats: \(error)")
            return [:]
        }
    }

    private func save(_ records: [String: Record]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            try storage.save(encoder.encode(records), to: filename)
        } catch {
            statsLogger.error("Could not save search stats: \(error)")
        }
    }
}
