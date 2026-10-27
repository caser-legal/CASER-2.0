import SwiftUI
import UserNotifications
import ActivityKit

struct SettingsView: View {
    enum Destination: Hashable {
        case saved
        case searchFees
        case notifications
        case recentSearches
        case recentMatches
        case about
        case support
        case terms
    }

    @Environment(SavingsTrackerStore.self) private var savingsStore
    @Environment(SavedCasesManager.self) private var savedManager
    @Environment(UserSettingsStore.self) private var userSettings
    @Environment(\.dismiss) private var dismissSettings
    @Environment(\.openURL) private var openURL
    @Binding var path: [Destination]
    @State private var showEraseConfirmation = false
    @State private var showEraseToast = false
    @State private var eraseErrorMessage: String?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    private let moreAppsURL = URL(string: "https://apps.apple.com/us/developer/adam-doherty/id1838643162")
    private let websiteURL = URLValidator.safeURL("https://caserlegal.com")
    private let writeReviewURL = URL(string: "itms-apps://apps.apple.com/app/id6752289799?action=write-review")

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: Destination.notifications) {
                        HStack {
                            Image(systemName: "bell")
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Notifications")
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                    
                    NavigationLink(value: Destination.recentSearches) {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Recent Searches")
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                    
                    NavigationLink(value: Destination.recentMatches) {
                        HStack {
                            Image(systemName: "bell.badge")
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Alert Matches")
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                    
                    NavigationLink(value: Destination.saved) {
                        HStack {
                            Image(systemName: "heart")
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Saved Cases")
                                .foregroundStyle(.white)
                            Spacer()
                            if !savedManager.savedCases.isEmpty {
                                Text(savedManager.savedCases.count.formatted())
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    
                    NavigationLink(value: Destination.searchFees) {
                        HStack {
                            Image(systemName: "dollarsign.circle")
                                .foregroundStyle(.white.opacity(0.85))
                            Text("PACER Savings Tracker")
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                } header: {
                    Text("Tools")
                }.listRowBackground(Rectangle().fill(.ultraThinMaterial))
                
                Section {
                    NavigationLink(value: Destination.about) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.white.opacity(0.85))
                            Text("About CASER")
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                    
                    NavigationLink(value: Destination.support) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Support")
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                    
                    NavigationLink(value: Destination.terms) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Terms & Privacy")
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                    
                    Button {
                        if let url = writeReviewURL {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Rate CASER")
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                    .accessibilityLabel("Rate CASER, opens the App Store")

                    if let websiteURL {
                        Link(destination: websiteURL) {
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundStyle(.white.opacity(0.85))
                                Text("Website")
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }

                    if let moreAppsURL {
                        Link(destination: moreAppsURL) {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.white.opacity(0.85))
                                Text("More Apps")
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }

                    Button {
                        hasCompletedOnboarding = false
                        dismissSettings()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle")
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Replay Onboarding")
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                    .accessibilityLabel("Replay onboarding")
                } header: {
                    Text("Information")
                }.listRowBackground(Rectangle().fill(.ultraThinMaterial))

                Section {
                    Button(role: .destructive) {
                        showEraseConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                            Text("Erase App Data")
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                    .accessibilityLabel("Erase app data")
                } header: {
                    Text("Privacy & Data")
                } footer: {
                    Text("Permanently delete saved cases, alerts, match history, search history, and savings tracker data from this device.")
                }.listRowBackground(Rectangle().fill(.ultraThinMaterial))

                Section {
                    let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                    Text("CASER v\(shortVersion) (\(build))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .accessibilityLabel("CASER version \(shortVersion), build \(build)")
                }.listRowBackground(Rectangle().fill(.ultraThinMaterial))
            }
            .scrollIndicators(.hidden)
            .confirmationDialog(
                "Erase app data?",
                isPresented: $showEraseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Erase App Data", role: .destructive) {
                    Task { await eraseAllLocalData() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes saved cases, alerts, match history, search history, and savings data. This cannot be undone.")
            }
            .alert(
                "Some Data Couldn't Be Erased",
                isPresented: Binding(
                    get: { eraseErrorMessage != nil },
                    set: { if !$0 { eraseErrorMessage = nil } }
                )
            ) {
                Button("OK") { eraseErrorMessage = nil }
            } message: {
                Text(eraseErrorMessage ?? "Some app data remains on this device. Please try again.")
            }
            .overlay(alignment: .bottom) {
                if showEraseToast {
                    Text("App data erased.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .scrollContentBackground(.hidden)
            .background {
                MainBackground()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .saved:
                    SavedCasesView()
                case .searchFees:
                    SearchFeesView()
                case .notifications:
                    NotificationsSettingsView()
                case .recentSearches:
                    RecentSearchesView()
                case .recentMatches:
                    RecentMatchesView()
                case .about:
                    AboutView()
                case .support:
                    SupportView()
                case .terms:
                    TermsPrivacyView()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSearchFees)) { _ in
                path = [.searchFees]
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNotifications)) { _ in
                path = [.notifications]
            }
        }
    }

    @MainActor
    private func eraseAllLocalData() async {
        var failures: [String] = []
        savedManager.clearPersistenceError()

        if !(await savedManager.clearAll()) {
            failures.append("saved cases")
        }
        if !savedManager.resetLifetimeCount() {
            failures.append("saved-case history")
        }

        MonitorScanService.shared.cancelAll()
        KeywordMonitorStorage.shared.clear()
        if !KeywordMonitorStorage.shared.load().isEmpty {
            failures.append("alerts")
        }
        MatchCacheStorage.shared.clear()
        if !MatchCacheStorage.shared.load().isEmpty {
            failures.append("alert matches")
        }
        KeywordSearchStatsStorage.shared.clear()
        AlertResultsStorage.shared.clear()
        await CaserLiveActivity.endAll()

        PDFExporter.removeLeftoverExports()

        let searchHistory = SearchHistoryManager.shared
        searchHistory.clearHistory()
        if await !searchHistory.loadHistory().isEmpty {
            failures.append("search history")
        }

        if case .failure(let error) = await savingsStore.tracker.clearAllLifetimeData() {
            failures.append("savings data (\(error.localizedDescription))")
        }
        savingsStore.markStale(resetData: true)

        userSettings.resetAll()

        ActivityFeedStore.shared.clear()
        if !ActivityFeedStore.shared.load().isEmpty {
            failures.append("activity history")
        }

        MonitorDeliveryHistory.shared.clear()
        if !MonitorDeliveryHistory.shared.load().isEmpty {
            failures.append("notification delivery history")
        }

        UserDefaults.standard.removeObject(forKey: "com.caser.monitor.lastFeedOffset")
        UserDefaults.standard.removeObject(forKey: "first_search_completed")
        UserDefaults.standard.removeObject(forKey: "first_search_review_shown")
        UserDefaults.standard.removeObject(forKey: "hasSeenAIDisclaimer")
        AIDisclaimerConsent.shared.resetAcceptance()

        await NotificationManager.shared.clearAllNotifications()
        NotificationCenter.default.post(name: .monitorConfigurationDidChange, object: nil)

        guard failures.isEmpty else {
            savedManager.clearPersistenceError()
            let uniqueFailures = Array(Set(failures)).sorted()
            eraseErrorMessage = "CASER couldn't remove: \(uniqueFailures.joined(separator: ", ")). Other selected data was erased. Please try again."
            return
        }

        path = []
        withAnimation { showEraseToast = true }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation { showEraseToast = false }
        }
    }
}

struct NotificationsSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(UserSettingsStore.self) private var userSettings
    @State private var notificationsEnabled = false
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isReconciling = false
    @State private var liveActivitiesAllowed = true
    @State private var backgroundRefreshStatus: UIBackgroundRefreshStatus = .available

    private var systemFooter: String {
        switch authorizationStatus {
        case .denied:
            "Notifications are off for CASER in iOS Settings. Alerts still run and matches still appear in the Alerts tab. Tap the toggle to turn notifications on."
        case .authorized, .provisional, .ephemeral:
            "Allow CASER to send you alerts. You can change this any time in iOS Settings."
        case .notDetermined:
            "Allow CASER to send you alerts. iOS will ask for permission the first time you enable this."
        @unknown default:
            "Allow CASER to send you alerts. You can change this any time in iOS Settings."
        }
    }

    private var caseAlertsFooter: String {
        var text = "CASER checks courts for your alerts about every 30 minutes while it's open, and in the background as often as iOS allows. Matches always appear in the Alerts tab. With Show Alert Details off, notifications don't include the alert term or filing."
        if !liveActivitiesAllowed {
            text += " Live Activities are turned off for CASER in iOS Settings."
        }
        return text
    }

    private var backgroundRefreshLabel: String {
        switch backgroundRefreshStatus {
        case .available: "On"
        case .denied: "Off"
        case .restricted: "Restricted"
        @unknown default: "Unknown"
        }
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { notificationsEnabled },
                    set: { newValue in handleToggle(newValue) }
                )) {
                    HStack {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Push Notifications")
                            .foregroundStyle(.white)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Push notifications")
                .accessibilityHint(authorizationStatus == .denied ? "Opens iOS Settings to enable" : "Toggles push notifications for CASER")
            } header: {
                Text("System")
            } footer: {
                Text(systemFooter)
            }.listRowBackground(Rectangle().fill(.ultraThinMaterial))

            Section {
                Toggle(isOn: Binding(
                    get: { userSettings.monitorAlertsEnabled },
                    set: { userSettings.monitorAlertsEnabled = $0 }
                )) {
                    HStack {
                        Image(systemName: "bell")
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Case Alerts")
                            .foregroundStyle(.white)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityHint("Checks courts for your alert keywords and notifies you about new filings")

                Toggle(isOn: Binding(
                    get: { userSettings.showNotificationDetails },
                    set: { userSettings.showNotificationDetails = $0 }
                )) {
                    HStack {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Show Alert Details")
                            .foregroundStyle(.white)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityHint("Includes the alert term and filing in notifications")

                Toggle(isOn: Binding(
                    get: { userSettings.liveActivitiesEnabled },
                    set: { userSettings.liveActivitiesEnabled = $0 }
                )) {
                    HStack {
                        Image(systemName: "platter.filled.bottom.iphone")
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Live Activities")
                            .foregroundStyle(.white)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityHint("Shows each alert's latest results on the Lock Screen and Dynamic Island")
            } header: {
                Text("Case Alerts")
            } footer: {
                Text(caseAlertsFooter)
            }.listRowBackground(Rectangle().fill(.ultraThinMaterial))

            Section {
                Button {
                    if let url = URLValidator.safeSystemURL(UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Background App Refresh")
                            .foregroundStyle(.white)
                        Spacer()
                        Text(backgroundRefreshLabel)
                            .foregroundStyle(backgroundRefreshStatus == .available ? .white.opacity(0.6) : .yellow)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityHint("Opens CASER's page in iOS Settings")
            } header: {
                Text("Background Checks")
            } footer: {
                Text(backgroundRefreshStatus == .available
                     ? "iOS decides when background checks run, based on battery, network, and how often you use CASER. Pull to refresh on Alerts, or tap Search Now on an alert or its Live Activity, for an immediate check."
                     : "With Background App Refresh off (or Low Power Mode on), CASER can only check courts while it's open. Turn it on in Settings > General > Background App Refresh.")
            }.listRowBackground(Rectangle().fill(.ultraThinMaterial))
        }
        .scrollContentBackground(.hidden)
        .background {
            MainBackground()
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await refreshAuthorization()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refreshAuthorization() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.backgroundRefreshStatusDidChangeNotification)) { _ in
            backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        }
    }

    private func handleToggle(_ newValue: Bool) {
        notificationsEnabled = newValue

        switch authorizationStatus {
        case .notDetermined:
            Task {
                await NotificationManager.shared.requestAuthorizationIfNeeded()
                await refreshAuthorization()
            }
        case .denied, .authorized, .provisional, .ephemeral:
            NotificationManager.shared.openNotificationSettings()
            Task { await refreshAuthorization() }
        @unknown default:
            Task { await refreshAuthorization() }
        }
    }

    private func refreshAuthorization() async {
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        liveActivitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        authorizationStatus = status
        notificationsEnabled = (status == .authorized || status == .provisional || status == .ephemeral)
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(AppBranding.fullName) (\(AppBranding.aka)) is a powerful tool for tracking federal district and bankruptcy case filings. Search cases, set up keyword alerts, and stay informed about legal proceedings.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                }
            } header: {
                Text("About")
            }.listRowBackground(Rectangle().fill(.ultraThinMaterial))
            
            Section {
                HStack {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Encrypted Connections")
                        .foregroundStyle(.white)
                    Spacer()
                }
                
                HStack {
                    Image(systemName: "iphone")
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Local Data Storage")
                        .foregroundStyle(.white)
                    Spacer()
                }
                
                HStack {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(.white.opacity(0.85))
                    Text("No Account Required")
                        .foregroundStyle(.white)
                    Spacer()
                }
            } header: {
                Text("Security & Privacy")
            } footer: {
                Text("Most app data is stored locally on your device. Atticus insights on a case's Details page and answers to your follow-up questions are generated by Meta's Muse AI: the case details you open and the questions you ask are sent to Meta through CASER's server. Your saved cases, alerts, and search history are not sent. Network requests use TLS encryption. No account or login required.")
            }.listRowBackground(Rectangle().fill(.ultraThinMaterial))
            
            Section {
                HStack {
                    Text("Version")
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                        .foregroundStyle(.white)
                }
                .accessibilityElement(children: .combine)
                HStack {
                    Text("Build")
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                        .foregroundStyle(.white)
                }
                .accessibilityElement(children: .combine)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Built by Adam Doherty.")
                    Text("\u{00A9} 2026 CASER Legal. All rights reserved.")
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
            }.listRowBackground(Rectangle().fill(.ultraThinMaterial))
        }
        .scrollContentBackground(.hidden)
        .background {
            MainBackground()
        }
        .navigationTitle("About CASER")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct SupportView: View {
    @State private var showBugReport = false
    private let termsURL = URLValidator.safeURL("https://caserlegal.com/terms")
    private let privacyURL = URLValidator.safeURL("https://caserlegal.com/privacy")

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Our support team is here to help with technical problems or general inquiries about CASER.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                }
            } header: {
                Text("Contact Support")
            }.listRowBackground(Rectangle().fill(.ultraThinMaterial))
            
            Section {
                Button {
                    showBugReport = true
                } label: {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.white.opacity(0.85))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Email Support")
                                .foregroundStyle(.white)
                            Text(AppBranding.supportEmail)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Email support at \(AppBranding.supportEmail)")

                Button {
                    if let url = URLValidator.safeURL("mailto:\(AppBranding.supportEmail)?subject=CASER%20Feedback") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.white.opacity(0.85))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Feedback")
                                .foregroundStyle(.white)
                            Text("Suggest features or share ideas")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Send feedback to \(AppBranding.supportEmail)")
            } footer: {
                Text("Response time: typically within 24-48 hours.")
            }.listRowBackground(Rectangle().fill(.ultraThinMaterial))

            Section {
                HStack(alignment: .top) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Search Not Working")
                            .foregroundStyle(.white)
                        Text("Check your internet connection. Try clearing search filters. Restart the app if issues persist.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                
                HStack(alignment: .top) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Missing Alerts")
                            .foregroundStyle(.white)
                        Text("Make sure your alert is turned on and notifications are allowed in iOS Settings. CASER checks for new matches in the background when your phone allows it.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                
                HStack(alignment: .top) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Atticus Insights")
                            .foregroundStyle(.white)
                        Text("Atticus explains a case when you open its Details and needs an internet connection. Its answers come from Meta's Muse AI, can be wrong, and are information only, not legal advice.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            } header: {
                Text("Common Issues")
            }.listRowBackground(Rectangle().fill(.ultraThinMaterial))
            
            Section {
                if let termsURL {
                    Link(destination: termsURL) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Terms of Service")
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }

                if let privacyURL {
                    Link(destination: privacyURL) {
                        HStack {
                            Image(systemName: "hand.raised")
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Privacy Policy")
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            } header: {
                Text("Legal")
            } footer: {
                Text("Most app data is stored locally. Atticus insights and answers are generated by Meta's Muse AI from the case details you open and the questions you ask. No account required.")
            }.listRowBackground(Rectangle().fill(.ultraThinMaterial))
        }
        .scrollContentBackground(.hidden)
        .background {
            MainBackground()
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.large)
        .alert("Found a Bug?", isPresented: $showBugReport) {
            Button("Open Mail") {
                if let url = URLValidator.safeURL("mailto:\(AppBranding.supportEmail)?subject=CASER%20Bug%20Report") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will open your email client to send a bug report to \(AppBranding.supportEmail)")
        }
    }
}

private struct RecentSearchesView: View {
    private let historyManager = SearchHistoryManager.shared
    @State private var recentSearches: [SearchHistoryEntry] = []
    @State private var showClearConfirmation = false
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }.caserListRow()
            } else if recentSearches.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.6))
                        Text("No recent searches")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Your search history will appear here")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }.caserListRow()
            } else {
                Section {
                    ForEach(recentSearches) { entry in
                        NavigationLink(value: entry.id) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.query)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(recentSearchDetail(entry))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                        .caserListRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                historyManager.deleteEntry(entry.id)
                                recentSearches.removeAll { $0.id == entry.id }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    CaserSectionHeader(title: "History", trailing: recentSearches.count.formatted())
                } footer: {
                    Text("Tap a search to see the results it found.")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .listStyle(.insetGrouped)
        .caserListBackground()
        .navigationTitle("Recent Searches")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: UUID.self) { entryId in
            SearchHistoryDetailView(entryId: entryId)
        }
        .toolbar {
            if !recentSearches.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        showClearConfirmation = true
                    }
                    .foregroundStyle(.red)
                    .accessibilityLabel("Clear all recent searches")
                }
            }
        }
        .task {
            isLoading = true
            recentSearches = await historyManager.loadHistorySummaries()
            isLoading = false
        }
        .confirmationDialog(
            "Clear all recent searches?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                historyManager.clearHistory()
                recentSearches = []
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes your search history from this device.")
        }
    }

    private func recentSearchDetail(_ entry: SearchHistoryEntry) -> String {
        var parts = ["\(entry.resultCount.formatted()) \(entry.resultCount == 1 ? "result" : "results")"]
        if !entry.states.isEmpty {
            let states = entry.states.sorted()
            parts.append(states.count > 3 ? "\(states.prefix(3).joined(separator: ", ")) +\(states.count - 3)" : states.joined(separator: ", "))
        }
        parts.append(entry.timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
        return parts.joined(separator: " · ")
    }
}

private struct SearchHistoryDetailView: View {
    let entryId: UUID
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    private let historyManager = SearchHistoryManager.shared
    @State private var entry: SearchHistoryEntry?
    @State private var isLoading = true
    @State private var caseDetailPresentation: CaseDetailPresentation?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading saved results…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let entry {
                historyDetailContent(entry)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Couldn't load this search")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            MainBackground()
        }
        .navigationTitle("Search Results")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: entryId) {
            isLoading = true
            entry = await historyManager.loadEntry(id: entryId)
            isLoading = false
        }
        .sheet(item: $caseDetailPresentation) { presentation in
            CaseDetailView(
                entry: presentation.entry,
                matchedKeyword: presentation.matchedKeyword
            )
        }
    }

    @ViewBuilder
    private func historyDetailContent(_ entry: SearchHistoryEntry) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.query)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(summaryText(for: entry))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(filterSummary(for: entry))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.vertical, 4)
                .caserListRow()

                Button {
                    rerunSearch(entry)
                } label: {
                    Label("Search Again", systemImage: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.caserAccent)
                }
                .caserListRow()
            }

            if !entry.results.isEmpty {
                Section {
                    ForEach(entry.results) { result in
                        Button {
                            caseDetailPresentation = CaseDetailPresentation(id: result.id, entry: result, matchedKeyword: nil)
                        } label: {
                            CaseRow(item: result)
                        }
                        .buttonStyle(.plain)
                        .caserListRow()
                    }
                } header: {
                    CaserSectionHeader(title: "Results", trailing: entry.results.count.formatted())
                } footer: {
                    if entry.resultCount > entry.results.count {
                        Text("CASER keeps the first \(entry.results.count) of \(entry.resultCount.formatted()) results. Search again to see them all.")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .caserListBackground()
    }

    private func filterSummary(for entry: SearchHistoryEntry) -> String {
        var parts = ["Searched \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))"]
        if !entry.states.isEmpty { parts.append(entry.states.sorted().joined(separator: ", ")) }
        if !entry.courtTypes.isEmpty { parts.append(entry.courtTypes.sorted().joined(separator: ", ")) }
        if entry.dateRange != "All time" { parts.append(entry.dateRange) }
        return parts.joined(separator: " · ")
    }

    private func summaryText(for entry: SearchHistoryEntry) -> String {
        if entry.resultCount == 0 {
            return "No matches found"
        }
        if entry.results.isEmpty {
            return "\(entry.resultCount) results (not saved on device)"
        }
        if entry.resultCount > entry.results.count {
            return "\(entry.resultCount) results · showing \(entry.results.count) saved"
        }
        return "\(entry.resultCount) result\(entry.resultCount == 1 ? "" : "s")"
    }

    private func rerunSearch(_ entry: SearchHistoryEntry) {
        let userInfo: [String: Any] = [
            "query": entry.query, "states": entry.states,
            "courtTypes": entry.courtTypes, "dateRange": entry.dateRange
        ]
        router.selectedTab = .search
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            NotificationCenter.default.post(name: .performSearch, object: nil, userInfo: userInfo)
        }
    }
}

private struct RecentMatchesView: View {
    @State private var allMatches: [CaseMatch] = []
    @State private var visibleCount = PaginatedBatch.pageSize
    @State private var isLoading = true
    @State private var showClearConfirmation = false
    @State private var caseDetailPresentation: CaseDetailPresentation?
    private let matchStorage = MatchCacheStorage.shared

    private var visibleMatches: [CaseMatch] {
        PaginatedBatch.page(allMatches, visibleCount: visibleCount)
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }.caserListRow()
            } else if allMatches.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.badge")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.6))
                        Text("No recent alert matches")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Matches from your case alerts will appear here")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }.caserListRow()
            } else {
                Section {
                    ForEach(visibleMatches) { match in
                        Button {
                            open(match)
                        } label: {
                            CaseRow(item: match, isUnread: !match.read, isStarred: match.starred)
                        }
                        .buttonStyle(.plain)
                        .caserListRow()
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleMatchRead(match)
                            } label: {
                                Label(match.read ? "Unread" : "Read",
                                      systemImage: match.read ? "envelope.badge" : "envelope.open")
                            }
                            .tint(Color.caserAccent)
                        }
                        .contextMenu {
                            Button {
                                toggleMatchRead(match)
                            } label: {
                                Label(match.read ? "Mark as Unread" : "Mark as Read",
                                      systemImage: match.read ? "envelope.badge" : "envelope.open")
                            }
                            Button {
                                toggleMatchStarred(match)
                            } label: {
                                Label(match.starred ? "Unstar" : "Star", systemImage: match.starred ? "star.slash" : "star")
                            }
                            Button(role: .destructive) {
                                deleteMatch(match)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onAppear {
                            loadMoreMatchesIfNeeded(for: match.id)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteMatch(match)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    if PaginatedBatch.canLoadMore(totalCount: allMatches.count, visibleCount: visibleCount) {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(.white.opacity(0.6))
                            Spacer()
                        }
                    }
                } header: {
                    CaserSectionHeader(title: "Matches", trailing: allMatches.count.formatted())
                } footer: {
                    if allMatches.count > visibleCount {
                        Text("Showing \(visibleCount) of \(allMatches.count) matches.")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .caserListBackground()
        .navigationTitle("Alert Matches")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !allMatches.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        showClearConfirmation = true
                    }
                    .foregroundStyle(.red)
                    .accessibilityLabel("Clear all recent matches")
                }
            }
        }
        .task {
            await loadMatches()
        }
        .sheet(item: $caseDetailPresentation) { presentation in
            CaseDetailView(
                entry: presentation.entry,
                matchedKeyword: presentation.matchedKeyword
            )
        }
        .alert("Clear all recent matches?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                clearAllMatches()
            }
        } message: {
            Text("This permanently removes your alert match history and clears delivered notifications.")
        }
    }
    
    private func loadMatches() async {
        isLoading = true
        visibleCount = PaginatedBatch.pageSize
        let storage = matchStorage
        allMatches = await Task.detached(priority: .userInitiated) {
            let keywords = KeywordMonitorStorage.shared.load()
            return VisibleMatchProjection.filter(storage.load(), keywords: keywords)
        }.value
        isLoading = false
    }

    private func loadMoreMatchesIfNeeded(for matchID: String) {
        guard matchID == visibleMatches.last?.id else { return }
        guard PaginatedBatch.canLoadMore(totalCount: allMatches.count, visibleCount: visibleCount) else { return }
        visibleCount = PaginatedBatch.nextVisibleCount(current: visibleCount, totalCount: allMatches.count)
    }

    private func deleteMatch(_ match: CaseMatch) {
        allMatches.removeAll { $0.id == match.id }
        matchStorage.removeMatch(id: match.id)
        Task { await NotificationManager.shared.syncBadgeFromDelivered() }
    }

    private func open(_ match: CaseMatch) {
        caseDetailPresentation = CaseDetailPresentation(id: match.id, entry: match.asCaseEntry(), matchedKeyword: match.keyword)
        if !match.read { toggleMatchRead(match) }
    }

    private func toggleMatchRead(_ match: CaseMatch) {
        guard let index = allMatches.firstIndex(where: { $0.id == match.id }) else { return }
        allMatches[index].read.toggle()
        let isRead = allMatches[index].read
        matchStorage.updateMatch(id: match.id) { $0.read = isRead }
        Task { await NotificationManager.shared.syncBadgeFromDelivered() }
    }

    private func toggleMatchStarred(_ match: CaseMatch) {
        guard let index = allMatches.firstIndex(where: { $0.id == match.id }) else { return }
        allMatches[index].starred.toggle()
        let isStarred = allMatches[index].starred
        matchStorage.updateMatch(id: match.id) { $0.starred = isStarred }
    }

    private func clearAllMatches() {
        allMatches = []
        matchStorage.clear()
        Task { await NotificationManager.shared.clearAllNotifications() }
    }
}
