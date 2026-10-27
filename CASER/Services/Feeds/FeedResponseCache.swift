import Foundation

actor FeedResponseCache {
    static let shared = FeedResponseCache()

    struct Snapshot: Codable, Equatable, Sendable {
        let items: [RSSItem]
        let etag: String?
        let lastModified: String?

        var hasValidator: Bool { etag != nil || lastModified != nil }
    }

    private let storage: any MonitorFileStorage
    private let filename: String
    private var snapshots: [String: Snapshot]?
    private var isDirty = false

    init(filename: String = "court_feed_responses.json", storage: any MonitorFileStorage = SecureFileStore(protection: .completeUntilFirstUserAuthentication)) {
        self.filename = filename
        self.storage = storage
    }

    func snapshot(for url: URL) -> Snapshot? {
        loadIfNeeded()
        return snapshots?[url.absoluteString]
    }

    func store(items: [RSSItem], etag: String?, lastModified: String?, for url: URL) {
        store(Snapshot(items: items, etag: etag, lastModified: lastModified), for: url)
    }

    func store(_ snapshot: Snapshot, for url: URL) {
        loadIfNeeded()
        let key = url.absoluteString
        guard snapshot.hasValidator else {
            if snapshots?.removeValue(forKey: key) != nil { isDirty = true }
            return
        }
        guard snapshots?[key] != snapshot else { return }
        snapshots?[key] = snapshot
        isDirty = true
    }

    func flush() {
        guard isDirty, let snapshots, let data = try? JSONEncoder().encode(snapshots) else { return }
        do {
            try storage.save(data, to: filename)
            isDirty = false
        } catch { }
    }

    private func loadIfNeeded() {
        guard snapshots == nil else { return }
        if let data = try? storage.load(from: filename),
           let decoded = try? JSONDecoder().decode([String: Snapshot].self, from: data) {
            let usable = decoded.filter { $0.value.hasValidator }
            snapshots = usable
            isDirty = usable.count != decoded.count
        } else {
            snapshots = [:]
        }
    }
}
