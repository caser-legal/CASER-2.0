import Foundation
import os.log

private let resultsLogger = Logger(subsystem: "com.caser.app", category: "AlertResults")

struct AlertResultsStorage: Sendable {
    static let shared = AlertResultsStorage()

    static let maxFilingsPerFeed = 50

    struct Update: Sendable {
        let keywordId: String
        let signature: String
        let relevantFeedIDs: Set<String>
        let successfulFeedIDs: Set<String>
        let byFeed: [String: [CaseEntry]]
    }

    private struct Record: Codable {
        var signature: String
        var feeds: [String: [CaseEntry]]
    }

    private let filename = "monitor_alert_results.json"
    private let storage: any MonitorFileStorage

    init(storage: any MonitorFileStorage = SecureFileStore(protection: .completeUntilFirstUserAuthentication)) {
        self.storage = storage
    }

    func filings(for keyword: KeywordMonitor) -> [CaseEntry] {
        guard let record = loadRecords()[keyword.id], record.signature == keyword.matchSignature else { return [] }
        var seen = Set<String>()
        return record.feeds.values.joined()
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    }

    func apply(_ updates: [Update], existingKeywordIds: Set<String>) {
        var records = loadRecords().filter { existingKeywordIds.contains($0.key) }
        for update in updates where existingKeywordIds.contains(update.keywordId) {
            let previous = records[update.keywordId].flatMap { $0.signature == update.signature ? $0 : nil }
            var feeds = (previous?.feeds ?? [:]).filter { update.relevantFeedIDs.contains($0.key) }
            for id in update.successfulFeedIDs where update.relevantFeedIDs.contains(id) {
                let entries = update.byFeed[id] ?? []
                if entries.isEmpty {
                    feeds.removeValue(forKey: id)
                } else {
                    feeds[id] = Array(entries
                        .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                        .prefix(Self.maxFilingsPerFeed))
                }
            }
            records[update.keywordId] = Record(signature: update.signature, feeds: feeds)
        }
        save(records)
    }

    func remove(keywordId: String) {
        var records = loadRecords()
        guard records.removeValue(forKey: keywordId) != nil else { return }
        save(records)
    }

    func clear() {
        guard storage.exists(filename) else { return }
        do { try storage.delete(filename) }
        catch { resultsLogger.error("Could not clear alert results: \(error)") }
    }

    private func loadRecords() -> [String: Record] {
        guard storage.exists(filename) else { return [:] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode([String: Record].self, from: storage.load(from: filename))
        } catch {
            resultsLogger.error("Could not load alert results: \(error)")
            return [:]
        }
    }

    private func save(_ records: [String: Record]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            try storage.save(encoder.encode(records), to: filename)
        } catch {
            resultsLogger.error("Could not save alert results: \(error)")
        }
    }
}
