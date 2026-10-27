import Foundation

struct AtticusFollowUpRecord: Codable, Equatable, Sendable {
    let question: String
    let answer: CaseAnswer
}

struct AtticusCaseRecord: Codable, Equatable, Sendable {
    var insights: CaseInsights?
    var research: CaseResearch?
    var researchUpdatedAt: Date?
    var followUps: [AtticusFollowUpRecord] = []
    var lastOpenedAt = Date()
}

@MainActor
final class AtticusCaseStore {
    static let shared = AtticusCaseStore()

    private static let filename = "atticus_case_cache.json"
    private static let maximumRecords = 500

    private let storage = SecureFileStore()
    private var records: [String: AtticusCaseRecord] = [:]

    private init() {
        guard let data = try? storage.load(from: Self.filename) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([String: AtticusCaseRecord].self, from: data)) ?? [:]
    }

    func record(for key: String) -> AtticusCaseRecord? {
        records[key]
    }

    func update(_ key: String, _ change: (inout AtticusCaseRecord) -> Void) {
        var record = records[key] ?? AtticusCaseRecord()
        change(&record)
        record.lastOpenedAt = Date()
        records[key] = record
        trimIfNeeded()
        persist()
    }

    func removeAll() {
        records.removeAll()
        try? storage.delete(Self.filename)
    }

    private func trimIfNeeded() {
        guard records.count > Self.maximumRecords else { return }
        let overflow = records.count - Self.maximumRecords
        let oldest = records
            .sorted { $0.value.lastOpenedAt < $1.value.lastOpenedAt }
            .prefix(overflow)
            .map(\.key)
        for key in oldest {
            records.removeValue(forKey: key)
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? storage.save(data, to: Self.filename)
    }
}
