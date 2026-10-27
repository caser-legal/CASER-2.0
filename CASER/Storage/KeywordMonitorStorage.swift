import Foundation
import os.log

private let storageLogger = Logger(subsystem: "com.caser.app", category: "KeywordMonitorStorage")

protocol MonitorFileStorage: Sendable {
    func load(from filename: String) throws -> Data
    func save(_ data: Data, to filename: String) throws
    func exists(_ filename: String) -> Bool
    func delete(_ filename: String) throws
}

extension SecureFileStore: MonitorFileStorage {}

struct KeywordMonitorStorage: Sendable {
    static let shared = KeywordMonitorStorage()

    private let storageKey = "monitorKeywords"
    private let storageFile = "monitor_keywords.json"
    private let storage: any MonitorFileStorage

    init(storage: any MonitorFileStorage = SecureFileStore(protection: .completeUntilFirstUserAuthentication)) {
        self.storage = storage
    }

    func load() -> [KeywordMonitor] {
        do { return try loadVerified() }
        catch {
            storageLogger.error("Failed to load keywords: \(error)")
            return []
        }
    }

    func loadVerified() throws -> [KeywordMonitor] {
        if storage.exists(storageFile) {
            return try JSONDecoder().decode([KeywordMonitor].self, from: storage.load(from: storageFile))
        }
        guard let legacyData = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        let decoded = try JSONDecoder().decode([KeywordMonitor].self, from: legacyData)
        try save(decoded)
        return decoded
    }

    func save(_ keywords: [KeywordMonitor]) throws {
        let data = try JSONEncoder().encode(keywords)
        try storage.save(data, to: storageFile)
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func clear() {
        do {
            try storage.delete(storageFile)
        } catch {
            storageLogger.error("Failed to clear storage: \(error)")
        }
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

struct MatchCacheStorage: Sendable {
    static let shared = MatchCacheStorage()

    private let matchesKey = "monitorMatchesCache"
    private let syncKey = "monitorMatchesLastSync"
    private let storageFile = "monitor_matches_cache.json"
    private let storage: any MonitorFileStorage

    init(storage: any MonitorFileStorage = SecureFileStore(protection: .completeUntilFirstUserAuthentication)) {
        self.storage = storage
    }

    private struct MatchCachePayload: Codable, Sendable {
        let matches: [CaseMatch]
        let syncedAt: Date
        let lastScanAt: Date?
        var processedKeys: Set<String>? = nil
        var feedCheckedAt: [String: Date]? = nil
        var feedAttemptedAt: [String: Date]? = nil
        var processedKeyDates: [String: Date]? = nil
    }

    func load() -> [CaseMatch] {
        do { return try loadVerified() }
        catch {
            storageLogger.error("Failed to load matches: \(error)")
            return []
        }
    }

    func loadVerified() throws -> [CaseMatch] {
        try checkedPayload()?.matches ?? []
    }

    private func checkedPayload() throws -> MatchCachePayload? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if storage.exists(storageFile) {
            return try decoder.decode(MatchCachePayload.self, from: storage.load(from: storageFile))
        }
        guard let legacy = UserDefaults.standard.data(forKey: matchesKey) else { return nil }
        let matches = try decoder.decode([CaseMatch].self, from: legacy)
        let date = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: syncKey))
        let payload = MatchCachePayload(matches: matches, syncedAt: date, lastScanAt: nil)
        try persist(payload)
        return payload
    }

    func processedKeys() throws -> Set<String> {
        let payload = try checkedPayload()
        var keys = payload?.processedKeys ?? []
        if let dated = payload?.processedKeyDates { keys.formUnion(dated.keys) }
        for match in payload?.matches ?? [] {
            keys.insert(Self.identity(of: match))
        }
        return keys
    }

    private static func identity(of match: CaseMatch) -> String {
        MonitorMatchEngine.matchKey(keywordID: match.keywordId ?? "", caseID: match.caseId, courtID: match.courtId)
    }

    private static func identityDates(in payload: MatchCachePayload?, defaultDate: Date) -> [String: Date] {
        var dates = payload?.processedKeyDates ?? [:]
        for key in payload?.processedKeys ?? [] where dates[key] == nil {
            dates[key] = defaultDate
        }
        for match in payload?.matches ?? [] {
            let key = identity(of: match)
            if dates[key] == nil { dates[key] = match.pubDate ?? defaultDate }
        }
        return dates
    }

    private static func pruned(_ dates: [String: Date], keeping matches: [CaseMatch], at date: Date) -> [String: Date] {
        let cutoff = date.addingTimeInterval(-MonitorMatchEngine.identityRetention)
        let retained = Set(matches.map(identity(of:)))
        return dates.filter { $0.value >= cutoff || retained.contains($0.key) }
    }

    private static func feedDates(
        previous: MatchCachePayload?, successfulFeedIDs: Set<String>, attemptedFeedIDs: Set<String>, at date: Date
    ) -> (checked: [String: Date], attempted: [String: Date]) {
        var checked = previous?.feedCheckedAt ?? [:]
        for id in successfulFeedIDs { checked[id] = date }
        var attempted = previous?.feedAttemptedAt ?? previous?.feedCheckedAt ?? [:]
        for id in attemptedFeedIDs.union(successfulFeedIDs) { attempted[id] = date }
        return (checked, attempted)
    }

    func feedCheckDates() throws -> [String: Date] {
        try checkedPayload()?.feedCheckedAt ?? [:]
    }

    func feedAttemptDates() throws -> [String: Date] {
        let payload = try checkedPayload()
        return payload?.feedAttemptedAt ?? payload?.feedCheckedAt ?? [:]
    }

    func commitScan(matches: [CaseMatch], processedKeys: Set<String>, successfulFeedIDs: Set<String>, attemptedFeedIDs: Set<String> = [], at date: Date) throws {
        let previous = try checkedPayload()
        let known = Self.identityDates(in: previous, defaultDate: date)
        var identities: [String: Date] = [:]
        for key in processedKeys { identities[key] = known[key] ?? date }
        let feeds = Self.feedDates(previous: previous, successfulFeedIDs: successfulFeedIDs, attemptedFeedIDs: attemptedFeedIDs, at: date)
        try persist(MatchCachePayload(
            matches: matches, syncedAt: date,
            lastScanAt: successfulFeedIDs.isEmpty ? previous?.lastScanAt : date,
            processedKeys: nil, feedCheckedAt: feeds.checked, feedAttemptedAt: feeds.attempted,
            processedKeyDates: Self.pruned(identities, keeping: matches, at: date)
        ))
    }

    func mergeScan(
        newMatches: [CaseMatch],
        identityDates newIdentityDates: [String: Date],
        keywords: [KeywordMonitor],
        successfulFeedIDs: Set<String>,
        attemptedFeedIDs: Set<String>,
        at date: Date,
        isFullScan: Bool = true,
        trim: ([CaseMatch]) -> [CaseMatch]
    ) throws -> [CaseMatch] {
        let previous = try checkedPayload()
        let current = MonitorMatchEngine.backfillKeywordIds(matches: previous?.matches ?? [], keywords: keywords).matches
        var identities = Self.identityDates(in: previous, defaultDate: date)
        var added: [CaseMatch] = []
        for match in newMatches {
            let key = Self.identity(of: match)
            guard identities[key] == nil else { continue }
            identities[key] = newIdentityDates[key] ?? match.pubDate ?? date
            added.append(match)
        }
        let matches = trim(added + current)
        let feeds = Self.feedDates(previous: previous, successfulFeedIDs: successfulFeedIDs, attemptedFeedIDs: attemptedFeedIDs, at: date)
        try persist(MatchCachePayload(
            matches: matches,
            syncedAt: date,
            lastScanAt: isFullScan && !successfulFeedIDs.isEmpty ? date : previous?.lastScanAt,
            processedKeys: nil, feedCheckedAt: feeds.checked, feedAttemptedAt: feeds.attempted,
            processedKeyDates: Self.pruned(identities, keeping: matches, at: date)
        ))
        let retained = Set(matches.map(\.id))
        return added.filter { retained.contains($0.id) }
    }

    private func persist(_ payload: MatchCachePayload) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try storage.save(encoder.encode(payload), to: storageFile)
        UserDefaults.standard.removeObject(forKey: matchesKey)
        UserDefaults.standard.removeObject(forKey: syncKey)
    }

    func save(_ matches: [CaseMatch], syncedAt: Date) {
        writePayload(matches: matches, syncedAt: syncedAt, lastScanAt: lastScanAt)
    }

    func recordScanCompleted(at date: Date) {
        let matches = load()
        let syncedAt = lastSyncedAt ?? date
        writePayload(matches: matches, syncedAt: syncedAt, lastScanAt: date)
    }

    var lastScanAt: Date? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = try? storage.load(from: storageFile),
              let payload = try? decoder.decode(MatchCachePayload.self, from: data) else {
            return nil
        }
        return payload.lastScanAt
    }

    var lastSyncedAt: Date? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = try? storage.load(from: storageFile),
              let payload = try? decoder.decode(MatchCachePayload.self, from: data) else {
            let timestamp = UserDefaults.standard.double(forKey: syncKey)
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        return payload.syncedAt
    }

    @discardableResult
    func clearMatches() -> Bool {
        do {
            guard let previous = try checkedPayload() else { return true }
            try persist(MatchCachePayload(
                matches: [], syncedAt: previous.syncedAt, lastScanAt: previous.lastScanAt,
                processedKeys: nil, feedCheckedAt: previous.feedCheckedAt,
                feedAttemptedAt: previous.feedAttemptedAt,
                processedKeyDates: Self.identityDates(in: previous, defaultDate: Date())
            ))
            return true
        } catch {
            storageLogger.error("Failed to clear alert matches: \(error)")
            return false
        }
    }

    func clear() {
        do {
            try storage.delete(storageFile)
        } catch {
            storageLogger.error("Failed to clear storage: \(error)")
        }
        UserDefaults.standard.removeObject(forKey: matchesKey)
        UserDefaults.standard.removeObject(forKey: syncKey)
    }

    func updateMatch(id: String, mutate: (inout CaseMatch) -> Void) {
        var matches = load()
        guard let index = matches.firstIndex(where: { $0.id == id }) else { return }
        mutate(&matches[index])
        save(matches, syncedAt: lastSyncedAt ?? Date())
    }

    func markNotified(_ ids: Set<String>) {
        updateMatches(ids) { $0.notified = true }
    }

    func markRead(_ ids: Set<String>) {
        updateMatches(ids) { $0.read = true }
    }

    private func updateMatches(_ ids: Set<String>, mutate: (inout CaseMatch) -> Void) {
        guard !ids.isEmpty else { return }
        var matches = load()
        var changed = false
        for index in matches.indices where ids.contains(matches[index].id) {
            let before = (matches[index].notified, matches[index].read)
            mutate(&matches[index])
            if before != (matches[index].notified, matches[index].read) { changed = true }
        }
        guard changed else { return }
        save(matches, syncedAt: lastSyncedAt ?? Date())
    }

    func removeMatch(id: String) {
        var matches = load()
        let before = matches.count
        matches.removeAll { $0.id == id }
        guard matches.count != before else { return }
        save(matches, syncedAt: lastSyncedAt ?? Date())
    }

    func removeMatches(forKeywordId keywordId: String) {
        var matches = load()
        let before = matches.count
        matches.removeAll { $0.keywordId == keywordId }
        guard matches.count != before else { return }
        save(matches, syncedAt: lastSyncedAt ?? Date())
    }

    private func writePayload(matches: [CaseMatch], syncedAt: Date, lastScanAt: Date?) {
        do {
            let previous = try checkedPayload()
            let payload = MatchCachePayload(
                matches: matches, syncedAt: syncedAt, lastScanAt: lastScanAt,
                processedKeys: nil, feedCheckedAt: previous?.feedCheckedAt,
                feedAttemptedAt: previous?.feedAttemptedAt,
                processedKeyDates: Self.identityDates(in: previous, defaultDate: Date())
            )
            try persist(payload)
        } catch {
            storageLogger.error("Failed to save data: \(error)")
        }
    }
}
