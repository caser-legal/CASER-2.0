import Foundation
import UserNotifications
import UIKit
import os.log

private let notificationLogger = Logger(subsystem: "com.caser.app", category: "NotificationManager")

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let userSettings = UserSettingsStore.shared

    var onNotificationTapped: ((String) -> Void)? {
        didSet {
            if let pending = pendingTap, let handler = onNotificationTapped {
                pendingTap = nil
                handler(pending)
            }
        }
    }

    private var pendingTap: String?
    private var didBecomeActiveObserver: NSObjectProtocol?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
        setupObservers()
    }

    private func registerNotificationCategories() {
        let markRead = UNNotificationAction(
            identifier: MonitorNotificationContent.markReadAction,
            title: "Mark as Read",
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")
        )
        let category = UNNotificationCategory(
            identifier: MonitorNotificationContent.category,
            actions: [markRead],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "New case alert",
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func setupObservers() {
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.syncBadgeFromDelivered()
            }
        }
    }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            notificationLogger.error("Failed to request notification authorization: \(error)")
        }
    }

    func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func isAuthorized() async -> Bool {
        let status = await checkPermissionStatus()
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func resetMonitorBadge() async {
        await setMonitorBadgeCount(0)
    }

    func setMonitorBadgeCount(_ count: Int) async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
            userSettings.monitorBadgeCount = count
        } catch {
            notificationLogger.error("Failed to set badge count: \(error.localizedDescription)")
        }
    }

    func clearAllNotifications() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        await resetMonitorBadge()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let matchID = userInfo["matchId"] as? String
        var matchIDs = Set(userInfo["matchIds"] as? [String] ?? [])
        if let matchID { matchIDs.insert(matchID) }

        switch response.actionIdentifier {
        case MonitorNotificationContent.markReadAction:
            await markRead(matchIDs)
        case UNNotificationDefaultActionIdentifier:
            await open(matchID: matchID, matchIDs: matchIDs)
        default:
            break
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    private func open(matchID: String?, matchIDs: Set<String>) {
        MonitorDeliveryHistory.shared.markOpened(matchIDs: matchIDs)
        guard let matchID else { return }
        if let handler = onNotificationTapped {
            handler(matchID)
        } else {
            pendingTap = matchID
        }
    }

    private func markRead(_ matchIDs: Set<String>) async {
        guard !matchIDs.isEmpty else { return }
        MatchCacheStorage.shared.markRead(matchIDs)
        NotificationCenter.default.post(name: .monitorMatchesDidChange, object: nil)
        await syncBadgeFromDelivered()
        await CaserLiveActivity.sync()
    }
}

extension NotificationManager {
    func syncBadgeFromDelivered() async {
        let totalUnread = MatchCacheStorage.shared.load().filter { !$0.read }.count
        if totalUnread != userSettings.monitorBadgeCount {
            await setMonitorBadgeCount(totalUnread)
        }
    }
}

enum MonitorNotificationContent {
    static let category = "MONITOR_ALERT"
    static let markReadAction = "MONITOR_MARK_READ"
    private static let maxMatchIDs = 100

    static func alert(matches: [CaseMatch], keyword: KeywordMonitor?, showDetails: Bool, badge: Int) -> UNMutableNotificationContent {
        let latest = matches[0]
        let content = base(matches: matches, badge: badge)
        content.threadIdentifier = "keyword-monitor-\(latest.keywordId ?? latest.keyword)"
        content.userInfo["keywordId"] = latest.keywordId ?? ""
        if showDetails {
            content.title = keyword?.term ?? latest.keyword
            if matches.count == 1 {
                content.subtitle = latest.courtName ?? ""
                content.body = filingLine(latest)
            } else {
                content.subtitle = "\(matches.count) new filings"
                content.body = "Latest: \(filingLine(latest))" + (latest.courtName.map { " (\($0))" } ?? "")
            }
        } else {
            content.title = "Case Alert"
            content.body = matches.count == 1
                ? "A new filing matches one of your alerts."
                : "\(matches.count) new filings match one of your alerts."
        }
        if keyword?.isCritical == true {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1
        } else {
            content.relevanceScore = 0.6
        }
        return content
    }

    static func summary(matches: [CaseMatch], alertTerms: [String], showDetails: Bool, badge: Int) -> UNMutableNotificationContent {
        let content = base(matches: matches, badge: badge)
        content.threadIdentifier = "keyword-monitor-summary"
        content.title = "Case Alerts"
        if showDetails {
            let names = alertTerms.prefix(3).joined(separator: ", ")
            let more = alertTerms.count > 3 ? " and \(alertTerms.count - 3) more" : ""
            content.body = "\(matches.count) new filings for \(names)\(more)."
        } else {
            content.body = "\(matches.count) new filings match your alerts."
        }
        content.userInfo["summary"] = true
        content.userInfo["groupCount"] = alertTerms.count
        content.relevanceScore = 0.8
        return content
    }

    private static func base(matches: [CaseMatch], badge: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.categoryIdentifier = category
        content.badge = NSNumber(value: badge)
        content.userInfo = [
            "matchId": matches[0].id,
            "matchIds": matches.prefix(maxMatchIDs).map(\.id),
            "matchCount": matches.count,
            "keyword": matches[0].keyword
        ]
        return content
    }

    private static func filingLine(_ match: CaseMatch) -> String {
        var line = match.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = match.caseNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
           !number.isEmpty, !line.contains(number) {
            line += " · \(number)"
        }
        return String(line.prefix(180))
    }
}
