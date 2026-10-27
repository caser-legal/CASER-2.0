import Foundation

enum MonitorScheduleService {
    static let interval: TimeInterval = 30 * 60

    static func scanInterval(at date: Date = Date()) -> TimeInterval { interval }

    static func nextScanDate(after date: Date = Date()) -> Date {
        date.addingTimeInterval(interval)
    }

    static func isStale(lastSyncedAt: Date?, now: Date = Date()) -> Bool {
        guard let lastSyncedAt else { return true }
        return now >= nextScanDate(after: lastSyncedAt)
    }

    static func statusLabel(at date: Date = Date()) -> String { "Active · 30 min checks" }

    static func nextScanLabel(lastSyncedAt: Date?, now: Date = Date()) -> String {
        guard let lastSyncedAt else { return "Due now" }
        let remaining = nextScanDate(after: lastSyncedAt).timeIntervalSince(now)
        guard remaining > 0 else { return "Due now" }
        return "Next scan in \(Int(ceil(remaining / 60)))m"
    }

    static func scanIsEligible(monitorAlertsEnabled: Bool, enabledKeywordCount: Int) -> Bool {
        monitorAlertsEnabled && enabledKeywordCount > 0
    }
}
