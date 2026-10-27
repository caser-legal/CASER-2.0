import Foundation
import os.log

private let historyLogger = Logger(subsystem: "com.caser.app", category: "MonitorDeliveryHistory")

enum MonitorDeliveryState: String, Codable, Sendable {
    case delivered, failed, opened
}

struct MonitorDeliveryRecord: Identifiable, Codable, Sendable {
    let id: String
    let matchID: String
    let alertTerm: String
    let date: Date
    var state: MonitorDeliveryState
}

struct MonitorDeliveryHistory: Sendable {
    static let shared = MonitorDeliveryHistory()
    private static let legacyKey = "monitor.delivery.history"
    private let filename = "monitor_delivery_history.json"
    private let limit = 200
    private let storage: any MonitorFileStorage

    init(storage: any MonitorFileStorage = SecureFileStore(protection: .completeUntilFirstUserAuthentication)) {
        self.storage = storage
    }

    func load() -> [MonitorDeliveryRecord] {
        if storage.exists(filename) {
            do {
                return try JSONDecoder().decode([MonitorDeliveryRecord].self, from: storage.load(from: filename))
            } catch {
                historyLogger.error("Could not read delivery history: \(error)")
                return []
            }
        }
        guard let data = UserDefaults.standard.data(forKey: Self.legacyKey),
              let records = try? JSONDecoder().decode([MonitorDeliveryRecord].self, from: data) else { return [] }
        if save(records) { UserDefaults.standard.removeObject(forKey: Self.legacyKey) }
        return records
    }

    func record(matchID: String, alertTerm: String, state: MonitorDeliveryState) {
        record([(matchID, alertTerm)], state: state)
    }

    func record(_ deliveries: [(matchID: String, alertTerm: String)], state: MonitorDeliveryState) {
        guard !deliveries.isEmpty else { return }
        let now = Date()
        let new = deliveries.reversed().map {
            MonitorDeliveryRecord(id: UUID().uuidString, matchID: $0.matchID, alertTerm: $0.alertTerm, date: now, state: state)
        }
        save(Array((new + load()).prefix(limit)))
    }

    func markOpened(matchIDs: Set<String>) {
        guard !matchIDs.isEmpty else { return }
        var records = load()
        var changed = false
        for index in records.indices where matchIDs.contains(records[index].matchID) && records[index].state != .opened {
            records[index].state = .opened
            changed = true
        }
        if changed { save(records) }
    }

    func markOpened(matchID: String) {
        markOpened(matchIDs: [matchID])
    }

    @discardableResult
    private func save(_ records: [MonitorDeliveryRecord]) -> Bool {
        do {
            try storage.save(JSONEncoder().encode(records), to: filename)
            return true
        } catch {
            historyLogger.error("Could not save delivery history: \(error)")
            return false
        }
    }

    func clear() {
        do { try storage.delete(filename) }
        catch { historyLogger.error("Could not clear delivery history: \(error)") }
        UserDefaults.standard.removeObject(forKey: Self.legacyKey)
    }
}
