import Foundation
import Observation

extension Notification.Name {
    static let userSettingsMonitorAlertsDidChange = Notification.Name("UserSettingsStore.monitorAlertsDidChange")
    static let userSettingsLiveActivitiesDidChange = Notification.Name("UserSettingsStore.liveActivitiesDidChange")
}

@MainActor
@Observable
final class UserSettingsStore {
    static let shared = UserSettingsStore()
    
    private enum Keys {
        static let monitorAlertsEnabled = "monitorAlertsEnabled"
        static let monitorBadgeCount = "MonitorBadgeCount"
        static let showNotificationDetails = "showNotificationDetails"
        static let liveActivitiesEnabled = "liveActivitiesEnabled"
    }
    
    private let defaults = UserDefaults.standard
    
    nonisolated static let alertLimit = 100
    
    var monitorAlertsEnabled: Bool {
        didSet {
            guard monitorAlertsEnabled != oldValue else { return }
            defaults.set(monitorAlertsEnabled, forKey: Keys.monitorAlertsEnabled)
            NotificationCenter.default.post(name: .userSettingsMonitorAlertsDidChange, object: monitorAlertsEnabled)
        }
    }
    
    var showNotificationDetails: Bool {
        didSet {
            guard showNotificationDetails != oldValue else { return }
            defaults.set(showNotificationDetails, forKey: Keys.showNotificationDetails)
            NotificationCenter.default.post(name: .userSettingsLiveActivitiesDidChange, object: liveActivitiesEnabled)
        }
    }

    var liveActivitiesEnabled: Bool {
        didSet {
            guard liveActivitiesEnabled != oldValue else { return }
            defaults.set(liveActivitiesEnabled, forKey: Keys.liveActivitiesEnabled)
            NotificationCenter.default.post(name: .userSettingsLiveActivitiesDidChange, object: liveActivitiesEnabled)
        }
    }

    var monitorBadgeCount: Int {
        didSet {
            guard monitorBadgeCount != oldValue else { return }
            defaults.set(monitorBadgeCount, forKey: Keys.monitorBadgeCount)
        }
    }
    
    private init() {
        if defaults.object(forKey: Keys.monitorAlertsEnabled) == nil {
            monitorAlertsEnabled = true
        } else {
            monitorAlertsEnabled = defaults.bool(forKey: Keys.monitorAlertsEnabled)
        }
        showNotificationDetails = defaults.object(forKey: Keys.showNotificationDetails) as? Bool ?? true
        liveActivitiesEnabled = defaults.object(forKey: Keys.liveActivitiesEnabled) as? Bool ?? true
        monitorBadgeCount = defaults.integer(forKey: Keys.monitorBadgeCount)
    }
    
    func resetAll() {
        monitorAlertsEnabled = true
        showNotificationDetails = true
        liveActivitiesEnabled = true
        monitorBadgeCount = 0
    }
}
