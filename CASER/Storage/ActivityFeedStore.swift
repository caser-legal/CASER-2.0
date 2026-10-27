import Foundation
import os.log

private let activityFeedLogger = Logger(subsystem: "com.caser.app", category: "ActivityFeedStore")

struct ActivityFeedStore: Sendable {
    static let shared = ActivityFeedStore()

    private let legacyKey = "LocalActivityFeed"
    private let storageFile = "local_activity_feed.json"
    private let storage = SecureFileStore()

    func load() -> [ActivityEntry] {
        if let data = UserDefaults.standard.data(forKey: legacyKey) {
            if let entries = try? JSONDecoder().decode([ActivityEntry].self, from: data) {
                try? storage.save(data, to: storageFile)
                UserDefaults.standard.removeObject(forKey: legacyKey)
                return entries
            }
        }
        guard let data = try? storage.load(from: storageFile),
              let entries = try? JSONDecoder().decode([ActivityEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func save(_ entries: [ActivityEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            try storage.save(data, to: storageFile)
            UserDefaults.standard.removeObject(forKey: legacyKey)
        } catch {
            activityFeedLogger.error("Failed to save activity feed: \(error)")
        }
    }

    func clear() {
        do {
            try storage.delete(storageFile)
        } catch {
            activityFeedLogger.error("Failed to clear activity feed: \(error)")
        }
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }
}