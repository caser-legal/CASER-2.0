import SwiftUI
import UserNotifications
import BackgroundTasks
import UIKit
import os.log

private let appLogger = Logger(subsystem: "com.caser.app", category: "CASERApp")

extension Notification.Name {
    static let monitorConfigurationDidChange = Notification.Name("CASER.monitorConfigurationDidChange")
}

private enum MonitorSchedulingEligibility {
    case idle
    case deferred
    case eligible
}

enum BGTaskID: String {
    case refresh = "com.caser.refresh"
    case processing = "com.caser.processing"
}

@main
struct CASERApp: App {
    @State private var savingsStore = SavingsTrackerStore.shared
    @State private var userSettings = UserSettingsStore.shared
    @State private var savedCasesManager = SavedCasesManager()
    @State private var router = AppRouter()
    @State private var monitorReconciliationTask: Task<Void, Never>?
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .environment(savingsStore)
                .environment(userSettings)
                .environment(savedCasesManager)
                .environment(router)
                .onAppear {
                    setupNotificationHandler()
                    reconcileMonitorScheduling()
                }
                .onReceive(NotificationCenter.default.publisher(for: .userSettingsMonitorAlertsDidChange)) { _ in
                    reconcileMonitorScheduling()
                }
                .onReceive(NotificationCenter.default.publisher(for: .monitorConfigurationDidChange)) { _ in
                    reconcileMonitorScheduling()
                }
                .onReceive(NotificationCenter.default.publisher(for: .userSettingsLiveActivitiesDidChange)) { _ in
                    Task { await CaserLiveActivity.sync() }
                }
                .onOpenURL { url in
                    if let keywordId = CaserDeepLink.alertKeywordId(from: url) {
                        router.openMonitor(keywordId: keywordId)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        reconcileMonitorScheduling()
                    case .background:
                        MonitorForegroundScheduler.shared.stop()
                        delegate.scheduleBackgroundWorkIfNeeded()
                        Task { await CaserLiveActivity.sync() }
                    default:
                        break
                    }
                }
        }
    }

    private func setupNotificationHandler() {
        NotificationManager.shared.onNotificationTapped = { matchId in
            Task { @MainActor in
                router.openMonitor(matchId: matchId)
            }
        }
    }

    private func reconcileMonitorScheduling() {
        monitorReconciliationTask?.cancel()
        monitorReconciliationTask = Task { @MainActor in
            guard !Task.isCancelled else { return }

            if scenePhase == .active,
               MonitorForegroundScheduler.scanIsEligible() {
                MonitorForegroundScheduler.shared.start()
            } else {
                MonitorForegroundScheduler.shared.stop()
            }

            await delegate.reconcileBackgroundWork()
            await CaserLiveActivity.sync()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        _ = NotificationManager.shared
        DataProtectionMigration.runIfNeeded()
        PDFExporter.removeLeftoverExports()
        registerBackgroundTasks()
        scheduleBackgroundWorkIfNeeded()
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        DataProtectionMigration.runIfNeeded()
    }

    private func registerBackgroundTasks() {
        for id in [BGTaskID.refresh, BGTaskID.processing] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: id.rawValue, using: .main) { [weak self] task in
                self?.performBackgroundScan(task: task)
            }
        }
    }

    private func performBackgroundScan(task: BGTask) {
        let completion = BackgroundTaskCompletion(task)
        let isRefresh = task is BGAppRefreshTask
        task.expirationHandler = { @Sendable in
            completion.complete(success: false)
            Task { @MainActor in MonitorScanService.shared.cancelAll() }
        }

        Task {
            let eligibility = await self.monitorScanEligibility()
            guard eligibility != .idle else {
                appLogger.info("Background scan skipped: no enabled alerts")
                completion.complete(success: true)
                return
            }
            if isRefresh { self.scheduleRefreshTask() } else { self.scheduleProcessingTask() }
            guard eligibility == .eligible, !completion.isComplete else {
                appLogger.info("Background scan deferred until alerts can be verified")
                completion.complete(success: true)
                return
            }
            let newMatches = await MonitorScanService.shared.scan(timeBudget: isRefresh ? 18 : 90)
            appLogger.info("Background scan found \(newMatches) new matches")
            completion.complete(success: MonitorScanService.shared.didCompleteLastScan)
        }
    }

    func scheduleBackgroundWorkIfNeeded() {
        Task {
            await self.reconcileBackgroundWork()
        }
    }

    func reconcileBackgroundWork() async {
        switch await monitorScanEligibility() {
        case .idle:
            cancelPendingBackgroundTasks()
        case .deferred, .eligible:
            let pending = await BGTaskScheduler.shared.pendingTaskRequests()
            if !pending.contains(where: { $0.identifier == BGTaskID.refresh.rawValue }) {
                scheduleRefreshTask()
            }
            if !pending.contains(where: { $0.identifier == BGTaskID.processing.rawValue }) {
                scheduleProcessingTask()
            }
        }
    }

    private func monitorScanEligibility() async -> MonitorSchedulingEligibility {
        guard UserSettingsStore.shared.monitorAlertsEnabled else { return .idle }
        do {
            guard try KeywordMonitorStorage.shared.loadVerified().contains(where: \.isSearchable) else { return .idle }
        } catch {
            return .deferred
        }
        return .eligible
    }

    private func cancelPendingBackgroundTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BGTaskID.refresh.rawValue)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BGTaskID.processing.rawValue)
    }

    @discardableResult
    private func scheduleRefreshTask() -> Bool {
        let refreshRequest = BGAppRefreshTaskRequest(identifier: BGTaskID.refresh.rawValue)
        refreshRequest.earliestBeginDate = MonitorScheduleService.nextScanDate()
        do {
            try BGTaskScheduler.shared.submit(refreshRequest)
            return true
        } catch {
            appLogger.error("Failed to schedule refresh task: \(error)")
            return false
        }
    }

    @discardableResult
    private func scheduleProcessingTask() -> Bool {
        let processingRequest = BGProcessingTaskRequest(identifier: BGTaskID.processing.rawValue)
        processingRequest.earliestBeginDate = MonitorScheduleService.nextScanDate()
        processingRequest.requiresNetworkConnectivity = true
        do {
            try BGTaskScheduler.shared.submit(processingRequest)
            return true
        } catch {
            appLogger.error("Failed to schedule processing task: \(error)")
            return false
        }
    }
}

final class BackgroundTaskCompletion: @unchecked Sendable {
    private let task: BGTask
    private let lock = NSLock()
    private var completed = false

    init(_ task: BGTask) {
        self.task = task
    }

    var isComplete: Bool {
        lock.withLock { completed }
    }

    func complete(success: Bool) {
        let shouldComplete = lock.withLock {
            defer { completed = true }
            return !completed
        }
        if shouldComplete { task.setTaskCompleted(success: success) }
    }
}

enum DataProtectionMigration {
    private static let doneKey = "dataProtection.classCMigrationDone"

    @MainActor
    static func runIfNeeded() {
        guard UIApplication.shared.isProtectedDataAvailable,
              !UserDefaults.standard.bool(forKey: doneKey) else { return }
        let fileManager = FileManager.default
        let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let roots = [
            library.appendingPathComponent("Preferences", isDirectory: true),
            library.appendingPathComponent("Caches", isDirectory: true),
            fileManager.temporaryDirectory
        ]
        Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            var failures = 0
            for root in roots where fileManager.fileExists(atPath: root.path) {
                if (try? fileManager.setAttributes(attributes, ofItemAtPath: root.path)) == nil { failures += 1 }
                let items = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)
                while let url = items?.nextObject() as? URL {
                    if (try? fileManager.setAttributes(attributes, ofItemAtPath: url.path)) == nil { failures += 1 }
                }
            }
            let failed = failures
            await MainActor.run {
                UserDefaults.standard.set(true, forKey: doneKey)
                appLogger.info("Data protection migration finished (\(failed) items not updated)")
            }
        }
    }
}
