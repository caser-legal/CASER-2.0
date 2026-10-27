import Foundation

extension Notification.Name {
    static let openSearchFees = Notification.Name("openSearchFees")
    static let openNewSearch = Notification.Name("openNewSearch")
    static let openSaved = Notification.Name("openSaved")
    static let openAddMonitor = Notification.Name("openAddMonitor")
    static let openNotifications = Notification.Name("openNotifications")
    static let openMonitorTab = Notification.Name("openMonitorTab")
    static let performSearch = Notification.Name("performSearch")
    static let monitorScanStarted = Notification.Name("monitorScanStarted")
    static let monitorScanCompleted = Notification.Name("monitorScanCompleted")
    static let monitorKeywordSearchDidChange = Notification.Name("monitorKeywordSearchDidChange")
    static let monitorMatchesDidChange = Notification.Name("monitorMatchesDidChange")
}
