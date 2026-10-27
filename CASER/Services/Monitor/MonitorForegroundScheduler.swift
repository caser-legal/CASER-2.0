import Foundation
import os.log

private let schedulerLogger = Logger(subsystem: "com.caser.app", category: "MonitorForegroundScheduler")

@MainActor
final class MonitorForegroundScheduler {
    static let shared = MonitorForegroundScheduler()

    private static let retryDelay: TimeInterval = 5 * 60

    private var loopTask: Task<Void, Never>?

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { await runLoop() }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func runLoop() async {
        while !Task.isCancelled {
            var delay = MonitorScheduleService.interval
            if Self.scanIsEligible() {
                let due = MonitorScheduleService.nextScanDate(after: MatchCacheStorage.shared.lastScanAt ?? .distantPast)
                if due <= Date() {
                    let newMatches = await MonitorScanService.shared.scan()
                    if newMatches > 0 {
                        schedulerLogger.info("Foreground scan found \(newMatches) new matches")
                    }
                    if !MonitorScanService.shared.didCompleteLastScan {
                        delay = Self.retryDelay
                    }
                } else {
                    delay = due.timeIntervalSinceNow
                }
            }
            do {
                try await Task.sleep(for: .seconds(max(delay, 30)))
            } catch {
                break
            }
        }
    }

    static func scanIsEligible() -> Bool {
        let settings = UserSettingsStore.shared
        let enabledCount = KeywordMonitorStorage.shared.load().filter(\.isSearchable).count
        return MonitorScheduleService.scanIsEligible(
            monitorAlertsEnabled: settings.monitorAlertsEnabled,
            enabledKeywordCount: enabledCount
        )
    }
}
