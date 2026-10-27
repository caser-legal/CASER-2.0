import Foundation
import os.log

let maxStoredResultsPerEntry = 100

struct SearchHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let query: String
    let states: [String]
    let courtTypes: [String]
    let dateRange: String
    let timestamp: Date
    let resultCount: Int
    let results: [CaseEntry]

    init(
        query: String,
        states: [String],
        courtTypes: [String] = [],
        dateRange: String = "All time",
        resultCount: Int,
        results: [CaseEntry] = []
    ) {
        self.init(
            id: UUID(),
            query: query,
            states: states,
            courtTypes: courtTypes,
            dateRange: dateRange,
            timestamp: Date(),
            resultCount: resultCount,
            results: results
        )
    }

    init(
        id: UUID,
        query: String,
        states: [String],
        courtTypes: [String],
        dateRange: String,
        timestamp: Date,
        resultCount: Int,
        results: [CaseEntry]
    ) {
        self.id = id
        self.query = query
        self.states = states
        self.courtTypes = courtTypes
        self.dateRange = dateRange
        self.timestamp = timestamp
        self.resultCount = resultCount
        self.results = Array(results.prefix(maxStoredResultsPerEntry))
    }

    func withoutResults() -> SearchHistoryEntry {
        SearchHistoryEntry(
            id: id,
            query: query,
            states: states,
            courtTypes: courtTypes,
            dateRange: dateRange,
            timestamp: timestamp,
            resultCount: resultCount,
            results: []
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SearchHistoryEntry, rhs: SearchHistoryEntry) -> Bool {
        lhs.id == rhs.id
    }

    enum CodingKeys: String, CodingKey {
        case id, query, states, courtTypes, dateRange, timestamp, resultCount, results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        query = try container.decode(String.self, forKey: .query)
        states = try container.decodeIfPresent([String].self, forKey: .states) ?? []
        courtTypes = try container.decodeIfPresent([String].self, forKey: .courtTypes) ?? []
        dateRange = try container.decodeIfPresent(String.self, forKey: .dateRange) ?? "All time"
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        resultCount = try container.decode(Int.self, forKey: .resultCount)
        let decodedResults = try container.decodeIfPresent([CaseEntry].self, forKey: .results) ?? []
        results = Array(decodedResults.prefix(maxStoredResultsPerEntry))
    }
}

@MainActor
class SearchHistoryManager {
    static let shared = SearchHistoryManager()

    private let userDefaultsKey = "SearchHistory"
    private let legacyKeychainKey = "com.caser.searchhistory"
    private let storageFile = "search_history.json"
    private let maxEntries = 20
    private let storage = SecureFileStore()
    private let logger = Logger(subsystem: "com.caser.app", category: "SearchHistory")

    private init() {
        migrateFromLegacyStores()
    }

    private var pendingWrite: Task<Void, Never>?

    @discardableResult
    func addEntry(
        query: String,
        states: [String],
        courtTypes: [String] = [],
        dateRange: String = "All time",
        resultCount: Int,
        results: [CaseEntry] = []
    ) -> SearchHistoryEntry {
        let entry = SearchHistoryEntry(
            query: query,
            states: states,
            courtTypes: courtTypes,
            dateRange: dateRange,
            resultCount: resultCount,
            results: results
        )
        let maxEntries = maxEntries
        write { history in
            history.removeAll { $0.query.caseInsensitiveCompare(query) == .orderedSame
                && Set($0.states) == Set(states) && Set($0.courtTypes) == Set(courtTypes) && $0.dateRange == dateRange }
            history.insert(entry, at: 0)
            if history.count > maxEntries {
                history = Array(history.prefix(maxEntries))
            }
        }
        return entry.withoutResults()
    }

    func loadHistory() async -> [SearchHistoryEntry] {
        await pendingWrite?.value
        let storage = storage
        let storageFile = storageFile
        return await Task.detached(priority: .userInitiated) {
            Self.decodeHistory(storage: storage, file: storageFile, includeResults: true)
        }.value
    }

    func loadHistorySummaries() async -> [SearchHistoryEntry] {
        await pendingWrite?.value
        let storage = storage
        let storageFile = storageFile
        return await Task.detached(priority: .userInitiated) {
            Self.decodeHistory(storage: storage, file: storageFile, includeResults: false)
        }.value
    }

    func loadEntry(id: UUID) async -> SearchHistoryEntry? {
        await pendingWrite?.value
        let storage = storage
        let storageFile = storageFile
        return await Task.detached(priority: .userInitiated) {
            Self.decodeHistory(storage: storage, file: storageFile, includeResults: true)
                .first { $0.id == id }
        }.value
    }

    func clearHistory() {
        write { $0.removeAll() }
        cleanupLegacyStores()
    }

    func deleteEntry(_ id: UUID) {
        write { history in history.removeAll { $0.id == id } }
    }

    private func write(_ change: @escaping @Sendable (inout [SearchHistoryEntry]) -> Void) {
        let previous = pendingWrite
        let storage = storage
        let storageFile = storageFile
        pendingWrite = Task.detached(priority: .utility) {
            await previous?.value
            var history = Self.decodeHistory(storage: storage, file: storageFile, includeResults: true)
            change(&history)
            Self.save(history, storage: storage, file: storageFile)
        }
    }

    nonisolated private static func save(_ history: [SearchHistoryEntry], storage: SecureFileStore, file: String) {
        do {
            if history.isEmpty {
                if storage.exists(file) { try storage.delete(file) }
            } else {
                try storage.save(JSONEncoder().encode(history), to: file)
            }
        } catch {
            Logger(subsystem: "com.caser.app", category: "SearchHistory")
                .error("Error saving search history: \(error)")
        }
    }

    nonisolated private static func decodeHistory(
        storage: SecureFileStore,
        file: String,
        includeResults: Bool
    ) -> [SearchHistoryEntry] {
        do {
            let data = try storage.load(from: file)
            let history = try JSONDecoder().decode([SearchHistoryEntry].self, from: data)
            if includeResults {
                return history
            }
            return history.map { $0.withoutResults() }
        } catch {
            if storage.exists(file) {
                Logger(subsystem: "com.caser.app", category: "SearchHistory")
                    .error("Error loading search history from SecureFileStore")
            }
            return []
        }
    }

    private func migrateFromLegacyStores() {
        guard !storage.exists(storageFile) else {
            cleanupLegacyStores()
            return
        }

        if migrateFromKeychain() {
            return
        }

        migrateFromUserDefaults()
    }

    private func migrateFromKeychain() -> Bool {
        let data: Data
        do {
            data = try KeychainHelper.load(for: legacyKeychainKey)
        } catch KeychainHelper.KeychainError.itemNotFound {
            return false
        } catch {
            logger.error("Error reading Keychain during search history migration: \(error)")
            return false
        }

        guard let history = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) else {
            logger.error("Failed to decode search history from Keychain during migration")
            return false
        }

        do {
            let encoded = try JSONEncoder().encode(history)
            try storage.save(encoded, to: storageFile)
            cleanupLegacyStores()
            logger.info("Successfully migrated \(history.count) search history entries from Keychain to SecureFileStore")
            return true
        } catch {
            logger.error("Failed to migrate search history from Keychain to SecureFileStore: \(error)")
            return false
        }
    }

    private func migrateFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let history = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) else {
            return
        }

        do {
            let encoded = try JSONEncoder().encode(history)
            try storage.save(encoded, to: storageFile)
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            logger.info("Successfully migrated \(history.count) search history entries from UserDefaults to SecureFileStore")
        } catch {
            logger.error("Failed to migrate search history from UserDefaults to SecureFileStore: \(error)")
        }
    }

    private func cleanupLegacyStores() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        cleanupLegacyKeychain()
    }

    private func cleanupLegacyKeychain() {
        do {
            try KeychainHelper.delete(for: legacyKeychainKey)
        } catch KeychainHelper.KeychainError.itemNotFound {
        } catch {
            logger.error("Error clearing legacy Keychain search history: \(error)")
        }
    }
}
