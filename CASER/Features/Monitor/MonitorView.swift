import SwiftUI
import UIKit

struct MonitorView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SavedCasesManager.self) private var savedManager
    @State private var keywords: [KeywordMonitor] = []
    @State private var recentMatches: [CaseMatch] = []
    @State private var path: [String] = []
    @State private var showAddKeyword = false
    @State private var keywordPrefill: AlertKeywordPrefill?
    @State private var editingKeyword: KeywordMonitor?
    @State private var keywordToDelete: KeywordMonitor?
    @State private var saveError: String?
    @State private var exportError: String?
    @State private var showClearMatchesConfirmation = false
    @State private var pdfPreviewItem: PDFPreviewItem?
    @State private var caseDetailPresentation: CaseDetailPresentation?
    @State private var isScanning = false
    @State private var isPreparingPDFExport = false
    @State private var lastScanAt: Date?
    @State private var searchStats: [String: KeywordSearchStats] = [:]
    @State private var activeSearches: [String: CaserAlertAttributes.ActiveSearch] = [:]
    @State private var searchingKeywordIds: Set<String> = []
    @State private var notificationsDenied = false
    @State private var backgroundRefreshUnavailable = false
    private let matchStorage = MatchCacheStorage.shared
    private let settings = UserSettingsStore.shared

    private static let latestMatchLimit = 5

    private var unreadCountByKeywordId: [String: Int] {
        recentMatches.reduce(into: [:]) { counts, match in
            guard !match.read, let keywordId = match.keywordId else { return }
            counts[keywordId, default: 0] += 1
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let banner = deliveryBanner {
                    Section { banner }
                        .caserListRow()
                }
                alertsSection
                latestMatchesSection
            }
            .listStyle(.insetGrouped)
            .caserListBackground()
            .refreshable {
                await MonitorScanService.shared.scan()
                reloadAll()
            }
            .navigationTitle("Case Alerts")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: String.self) { keywordId in
                AlertDetailView(keywordId: keywordId)
            }
            .toolbar { toolbarContent }
            .alert("Clear all matches?", isPresented: $showClearMatchesConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) { clearAllMatches() }
            } message: {
                Text("This removes all alert matches from this device. Your alerts keep running.")
            }
            .confirmationDialog(
                "Delete \u{201C}\(keywordToDelete?.term ?? "")\u{201D}?",
                isPresented: Binding(get: { keywordToDelete != nil }, set: { if !$0 { keywordToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Alert", role: .destructive) {
                    if let keyword = keywordToDelete { deleteKeyword(keyword) }
                    keywordToDelete = nil
                }
            } message: {
                Text("CASER will stop checking courts for this term and remove its matches.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAddMonitor)) { notification in
                let term = notification.userInfo?["term"] as? String
                presentAddKeywordSheet(prefillTerm: term ?? "")
            }
            .sheet(isPresented: $showAddKeyword) {
                AddKeywordSheet(prefill: keywordPrefill) { newKeyword in
                    Task { await addKeyword(newKeyword) }
                }
            }
            .sheet(item: $editingKeyword) { keyword in
                EditKeywordSheet(keyword: keyword) { updatedKeyword in
                    updateKeyword(updatedKeyword)
                }
            }
            .pdfPreviewSheet(item: $pdfPreviewItem)
            .sheet(item: $caseDetailPresentation) { presentation in
                CaseDetailView(entry: presentation.entry, matchedKeyword: presentation.matchedKeyword)
            }
            .alert("Error", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: {
                if let saveError { Text(saveError) }
            }
            .alert("Export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK") { exportError = nil }
            } message: {
                if let exportError { Text(exportError) }
            }
            .onChange(of: router.pendingMonitorMatchId) { _, matchId in
                openPendingMatch(matchId)
            }
            .onChange(of: router.pendingMonitorKeywordId) { _, keywordId in
                openKeyword(keywordId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .monitorScanStarted)) { _ in
                isScanning = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .monitorScanCompleted)) { _ in
                isScanning = MonitorScanService.shared.isScanning
                reloadAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .monitorKeywordSearchDidChange)) { _ in
                let wasSearching = searchingKeywordIds
                refreshSearchState()
                if !wasSearching.isSubset(of: searchingKeywordIds) {
                    loadKeywords()
                    loadMatches()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .monitorMatchesDidChange)) { _ in
                loadMatches()
            }
            .onReceive(NotificationCenter.default.publisher(for: .monitorConfigurationDidChange)) { _ in
                loadKeywords()
                loadMatches()
                refreshSearchState()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                loadMatches()
                refreshSearchState()
                Task { await refreshDeliveryWarnings() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.backgroundRefreshStatusDidChangeNotification)) { _ in
                Task { await refreshDeliveryWarnings() }
            }
            .onAppear {
                reloadAll()
                isScanning = MonitorScanService.shared.isScanning
                openPendingMatch(router.pendingMonitorMatchId)
                openKeyword(router.pendingMonitorKeywordId)
                Task {
                    await refreshDeliveryWarnings()
                    if MonitorScheduleService.isStale(lastSyncedAt: matchStorage.lastScanAt),
                       MonitorForegroundScheduler.scanIsEligible() {
                        await MonitorScanService.shared.scan()
                    }
                    clearOrphanedPendingMatch()
                }
            }
        }
    }

    @ViewBuilder
    private var alertsSection: some View {
        Section {
            if keywords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                        .font(.largeTitle)
                        .foregroundStyle(Color.caserAccent)
                        .accessibilityHidden(true)
                    Text("No alerts yet")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Add a name, company, or docket number and CASER will tell you when it appears in a new federal court filing.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                    Button {
                        presentAddKeywordSheet(prefillTerm: "")
                    } label: {
                        Label("Add Alert", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.caserAccent)
                    .foregroundStyle(.black)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .caserListRow()
            } else {
                ForEach(keywords) { keyword in
                    NavigationLink(value: keyword.id) {
                        AlertRow(
                            keyword: keyword,
                            unreadCount: unreadCountByKeywordId[keyword.id] ?? 0,
                            lastSearch: searchStats[keyword.id],
                            activeSearch: activeSearches[keyword.id],
                            isSearching: searchingKeywordIds.contains(keyword.id),
                            isPaused: !settings.monitorAlertsEnabled
                        )
                    }
                    .caserListRow()
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            keywordToDelete = keyword
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingKeyword = keyword
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.gray)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            toggleKeyword(keyword)
                        } label: {
                            Label(keyword.enabled ? "Turn Off" : "Turn On",
                                  systemImage: keyword.enabled ? "bell.slash" : "bell")
                        }
                        .tint(keyword.enabled ? .gray : Color.caserAccent)
                    }
                    .contextMenu {
                        if keyword.enabled {
                            Button {
                                searchNow(keyword)
                            } label: {
                                Label("Search Now", systemImage: "magnifyingglass")
                            }
                            .disabled(searchingKeywordIds.contains(keyword.id))
                        }
                        Button {
                            toggleKeyword(keyword)
                        } label: {
                            Label(keyword.enabled ? "Turn Off" : "Turn On",
                                  systemImage: keyword.enabled ? "bell.slash" : "bell")
                        }
                        Button {
                            editingKeyword = keyword
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            keywordToDelete = keyword
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text(keywords.isEmpty ? "Alerts" : "\(keywords.count) \(keywords.count == 1 ? "Alert" : "Alerts")")
                Spacer()
                if isScanning {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.6))
                    Text("Checking courts")
                } else if let lastScanAt {
                    Text("Checked \(RelativeTime.short(lastScanAt))")
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
            .textCase(nil)
        }
    }

    @ViewBuilder
    private var latestMatchesSection: some View {
        if !recentMatches.isEmpty {
            Section {
                ForEach(recentMatches.prefix(Self.latestMatchLimit)) { match in
                    Button {
                        openMatch(match)
                    } label: {
                        CaseRow(item: match, isUnread: !match.read, isStarred: match.starred, badge: nil)
                    }
                    .buttonStyle(.plain)
                    .caserListRow()
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteMatch(match)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            setMatchRead(match, read: !match.read)
                        } label: {
                            Label(match.read ? "Unread" : "Read",
                                  systemImage: match.read ? "envelope.badge" : "envelope.open")
                        }
                        .tint(Color.caserAccent)
                    }
                    .contextMenu {
                        Button {
                            setMatchRead(match, read: !match.read)
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
                }
            } header: {
                CaserSectionHeader(title: "Latest Matches")
            } footer: {
                if recentMatches.count > Self.latestMatchLimit {
                    Text("Open an alert to see all of its matches.")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private var deliveryBanner: DeliveryBanner? {
        guard keywords.contains(where: \.isSearchable) else { return nil }
        if !settings.monitorAlertsEnabled {
            return DeliveryBanner(
                icon: "pause.circle.fill", tint: .yellow,
                title: "Alerts are paused",
                message: "Courts aren't being checked.",
                action: "Resume"
            ) { settings.monitorAlertsEnabled = true }
        }
        if notificationsDenied && keywords.contains(where: { $0.isSearchable && $0.notifyPush }) {
            return DeliveryBanner(
                icon: "bell.slash.fill", tint: .orange,
                title: "Notifications are off",
                message: "New matches only appear here.",
                action: "Turn On"
            ) { NotificationManager.shared.openNotificationSettings() }
        }
        if backgroundRefreshUnavailable {
            return DeliveryBanner(
                icon: "arrow.clockwise", tint: .white.opacity(0.7),
                title: "Background App Refresh is off",
                message: "CASER checks courts while it's open.",
                action: "Settings"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        return nil
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if !keywords.isEmpty || !recentMatches.isEmpty {
                Menu {
                    if keywords.contains(where: \.isSearchable) {
                        Button {
                            Task { await MonitorScanService.shared.scan() }
                        } label: {
                            Label("Check All Now", systemImage: "arrow.clockwise")
                        }
                        .disabled(isScanning)
                    }
                    if !recentMatches.isEmpty {
                        Button {
                            exportMatches()
                        } label: {
                            Label("Export Matches as PDF", systemImage: "doc.richtext")
                        }
                        .disabled(isPreparingPDFExport)
                        Button(role: .destructive) {
                            showClearMatchesConfirmation = true
                        } label: {
                            Label("Clear All Matches", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                presentAddKeywordSheet(prefillTerm: "")
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add alert")
        }
    }

    private func reloadAll() {
        loadKeywords()
        loadMatches()
        lastScanAt = matchStorage.lastScanAt
        refreshSearchState()
    }

    private func loadKeywords() {
        keywords = AlertCreationService.shared.loadKeywords()
    }

    private func loadMatches() {
        recentMatches = VisibleMatchProjection.filter(matchStorage.load(), keywords: keywords)
        lastScanAt = matchStorage.lastScanAt
    }

    private func refreshSearchState() {
        let service = MonitorScanService.shared
        searchStats = KeywordSearchStatsStorage.shared.load()
        activeSearches = service.activeSearches
        searchingKeywordIds = Set(keywords.map(\.id).filter { service.isSearching(keywordId: $0) })
    }

    private func refreshDeliveryWarnings() async {
        backgroundRefreshUnavailable = UIApplication.shared.backgroundRefreshStatus != .available
        notificationsDenied = await NotificationManager.shared.checkPermissionStatus() == .denied
    }

    private func openKeyword(_ keywordId: String?) {
        guard let keywordId else { return }
        router.pendingMonitorKeywordId = nil
        if keywords.isEmpty { loadKeywords() }
        guard keywords.contains(where: { $0.id == keywordId }) else { return }
        path = [keywordId]
    }

    private func openPendingMatch(_ matchId: String?) {
        guard let matchId, !matchId.isEmpty else { return }
        if recentMatches.isEmpty { loadMatches() }
        guard let match = recentMatches.first(where: { $0.id == matchId }) else { return }
        router.pendingMonitorMatchId = nil
        path = []
        openMatch(match)
    }

    private func clearOrphanedPendingMatch() {
        guard let pending = router.pendingMonitorMatchId else { return }
        guard !recentMatches.contains(where: { $0.id == pending }) else { return }
        router.pendingMonitorMatchId = nil
    }

    private func openMatch(_ match: CaseMatch) {
        caseDetailPresentation = CaseDetailPresentation(
            id: match.id, entry: match.asCaseEntry(), matchedKeyword: match.keyword
        )
        if !match.read { setMatchRead(match, read: true) }
    }

    private func presentAddKeywordSheet(prefillTerm: String) {
        let trimmed = prefillTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        keywordPrefill = trimmed.isEmpty ? nil : AlertKeywordPrefill(term: trimmed)
        showAddKeyword = true
    }

    private func searchNow(_ keyword: KeywordMonitor) {
        guard keyword.isSearchable, !searchingKeywordIds.contains(keyword.id) else { return }
        searchingKeywordIds.insert(keyword.id)
        Task {
            await MonitorScanService.shared.searchNow(keywordId: keyword.id)
            refreshSearchState()
            loadKeywords()
            loadMatches()
        }
    }

    private func exportMatches() {
        let matches = recentMatches
        isPreparingPDFExport = true
        Task { @MainActor in
            defer { isPreparingPDFExport = false }
            if let url = await PDFExporter.exportMatches(matches) {
                pdfPreviewItem = PDFPreviewItem(url: url, title: "Alert Matches")
            } else {
                exportError = "Could not create PDF. Try again or export fewer matches."
            }
        }
    }

    private func addKeyword(_ keyword: KeywordMonitor) async {
        do {
            let created = try await AlertCreationService.shared.createAlert(
                term: keyword.term,
                selectedStates: keyword.selectedStates,
                notifyPush: keyword.notifyPush,
                isCritical: keyword.isCritical,
                caseSensitive: keyword.caseSensitive,
                exactMatch: keyword.exactMatch,
                matchPartyNames: keyword.matchPartyNames,
                matchCaseNumbers: keyword.matchCaseNumbers,
                matchCourts: keyword.matchCourts,
                liveActivityEnabled: keyword.liveActivityEnabled
            )
            loadKeywords()
            loadMatches()
            searchingKeywordIds.insert(created.id)
            keywordPrefill = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func updateKeyword(_ updatedKeyword: KeywordMonitor) {
        do {
            let saved = try AlertCreationService.shared.updateAlert(updatedKeyword)
            if let index = keywords.firstIndex(where: { $0.id == saved.id }) {
                keywords[index] = saved
            } else {
                loadKeywords()
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func toggleKeyword(_ keyword: KeywordMonitor) {
        guard let index = keywords.firstIndex(where: { $0.id == keyword.id }) else { return }
        let enable = !keywords[index].enabled
        do {
            let updated = try AlertCreationService.shared.setAlertEnabled(
                term: keyword.term, keywordID: keyword.id, enabled: enable
            )
            keywords[index] = updated
            if enable { searchingKeywordIds.insert(updated.id) }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func deleteKeyword(_ keyword: KeywordMonitor) {
        do {
            try AlertCreationService.shared.deleteAlert(id: keyword.id)
            keywords.removeAll { $0.id == keyword.id }
            path.removeAll { $0 == keyword.id }
            loadMatches()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func setMatchRead(_ match: CaseMatch, read: Bool) {
        guard let index = recentMatches.firstIndex(where: { $0.id == match.id }) else { return }
        recentMatches[index].read = read
        matchStorage.updateMatch(id: match.id) { $0.read = read }
        Task {
            await NotificationManager.shared.syncBadgeFromDelivered()
            if let keywordId = match.keywordId { await CaserLiveActivity.update(keywordId: keywordId) }
        }
    }

    private func toggleMatchStarred(_ match: CaseMatch) {
        guard let index = recentMatches.firstIndex(where: { $0.id == match.id }) else { return }
        recentMatches[index].starred.toggle()
        let isStarred = recentMatches[index].starred
        matchStorage.updateMatch(id: match.id) { $0.starred = isStarred }
    }

    private func deleteMatch(_ match: CaseMatch) {
        recentMatches.removeAll { $0.id == match.id }
        matchStorage.removeMatch(id: match.id)
        Task {
            await NotificationManager.shared.syncBadgeFromDelivered()
            if let keywordId = match.keywordId { await CaserLiveActivity.update(keywordId: keywordId) }
        }
    }

    private func clearAllMatches() {
        guard matchStorage.clearMatches() else { return }
        recentMatches.removeAll()
        Task {
            await NotificationManager.shared.clearAllNotifications()
            await CaserLiveActivity.sync()
        }
    }
}

private struct AlertRow: View {
    let keyword: KeywordMonitor
    let unreadCount: Int
    let lastSearch: KeywordSearchStats?
    let activeSearch: CaserAlertAttributes.ActiveSearch?
    let isSearching: Bool
    let isPaused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(keyword.term)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(keyword.enabled ? .white : .white.opacity(0.5))
                        .lineLimit(1)
                    if keyword.liveActivityEnabled && keyword.enabled {
                        Image(systemName: "platter.filled.bottom.iphone")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                            .accessibilityLabel("Live Activity on")
                    }
                }
                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.caserAccent, in: Capsule())
                    .accessibilityLabel("\(unreadCount) unread")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusLine: some View {
        if isSearching, keyword.enabled {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Color.caserAccent)
                Text(searchingText)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
        } else {
            Text(summaryText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    private var searchingText: String {
        guard let activeSearch, activeSearch.courtsTotal > 0 else { return "Searching…" }
        return "Searching \(activeSearch.courtsSearched) of \(activeSearch.courtsTotal) courts"
    }

    private var summaryText: String {
        var parts = [CaserLiveActivity.scopeSummary(for: keyword)]
        if !keyword.enabled {
            parts.append("Off")
        } else if isPaused {
            parts.append("Paused")
        } else if let lastSearch {
            let count = lastSearch.matchingFilings
            parts.append("\(count.formatted()) matching \(count == 1 ? "filing" : "filings")")
            parts.append(RelativeTime.short(lastSearch.finishedAt))
        } else {
            parts.append("Not searched yet")
        }
        return parts.joined(separator: " · ")
    }
}

private struct DeliveryBanner: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action, action: perform)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(tint)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

enum RelativeTime {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604_800 { return "\(Int(interval / 86400))d ago" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct KeywordMonitor: Identifiable, Codable, Sendable {
    let id: String
    var term: String
    var enabled: Bool
    var notifyPush: Bool
    var isCritical: Bool
    var caseSensitive: Bool
    var exactMatch: Bool
    var selectedStates: Set<String>
    var createdAt: Date
    var monitoringStartedAt: Date
    var lastCheckedAt: Date?
    var matchPartyNames: Bool
    var matchCaseNumbers: Bool
    var matchCourts: Bool
    var scopedCourtId: String?
    var scopedFeedId: String?
    var liveActivityEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case id, term, enabled, notifyPush, isCritical, caseSensitive, exactMatch, selectedStates
        case createdAt, monitoringStartedAt, lastCheckedAt, matchPartyNames, matchCaseNumbers, matchCourts
        case scopedCourtId, scopedFeedId, liveActivityEnabled
    }

    init(term: String, enabled: Bool = true, notifyPush: Bool = true, isCritical: Bool = false, caseSensitive: Bool = false, exactMatch: Bool = false, selectedStates: Set<String> = [], monitoringStartedAt: Date? = nil, matchPartyNames: Bool = true, matchCaseNumbers: Bool = true, matchCourts: Bool = true, scopedCourtId: String? = nil, scopedFeedId: String? = nil, liveActivityEnabled: Bool = true) {
        self.id = UUID().uuidString
        self.term = term
        self.enabled = enabled
        self.notifyPush = notifyPush
        self.isCritical = isCritical
        self.caseSensitive = caseSensitive
        self.exactMatch = exactMatch
        self.selectedStates = Set(selectedStates.map(StateAbbreviations.canonicalCode(for:)))
        let now = Date()
        self.createdAt = now
        self.monitoringStartedAt = monitoringStartedAt ?? now
        self.lastCheckedAt = nil
        self.matchPartyNames = matchPartyNames
        self.matchCaseNumbers = matchCaseNumbers
        self.matchCourts = matchCourts
        self.scopedCourtId = scopedCourtId
        self.scopedFeedId = scopedFeedId
        self.liveActivityEnabled = liveActivityEnabled
    }

    init(id: String, term: String, enabled: Bool, notifyPush: Bool, isCritical: Bool, caseSensitive: Bool, exactMatch: Bool, selectedStates: Set<String>, createdAt: Date, monitoringStartedAt: Date, lastCheckedAt: Date?, matchPartyNames: Bool = true, matchCaseNumbers: Bool = true, matchCourts: Bool = true, scopedCourtId: String? = nil, scopedFeedId: String? = nil, liveActivityEnabled: Bool = true) {
        self.id = id
        self.term = term
        self.enabled = enabled
        self.notifyPush = notifyPush
        self.isCritical = isCritical
        self.caseSensitive = caseSensitive
        self.exactMatch = exactMatch
        self.selectedStates = Set(selectedStates.map(StateAbbreviations.canonicalCode(for:)))
        self.createdAt = createdAt
        self.monitoringStartedAt = monitoringStartedAt
        self.lastCheckedAt = lastCheckedAt
        self.matchPartyNames = matchPartyNames
        self.matchCaseNumbers = matchCaseNumbers
        self.matchCourts = matchCourts
        self.scopedCourtId = scopedCourtId
        self.scopedFeedId = scopedFeedId
        self.liveActivityEnabled = liveActivityEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        term = try container.decode(String.self, forKey: .term)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? "legacy-\(Data(term.lowercased().utf8).base64EncodedString())"
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        notifyPush = try container.decodeIfPresent(Bool.self, forKey: .notifyPush) ?? true
        isCritical = try container.decodeIfPresent(Bool.self, forKey: .isCritical) ?? false
        caseSensitive = try container.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
        exactMatch = try container.decodeIfPresent(Bool.self, forKey: .exactMatch) ?? false
        let decodedStates = try container.decodeIfPresent(Set<String>.self, forKey: .selectedStates) ?? []
        selectedStates = Set(decodedStates.map(StateAbbreviations.canonicalCode(for:)))
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        monitoringStartedAt = try container.decodeIfPresent(Date.self, forKey: .monitoringStartedAt) ?? createdAt
        matchPartyNames = try container.decodeIfPresent(Bool.self, forKey: .matchPartyNames) ?? true
        matchCaseNumbers = try container.decodeIfPresent(Bool.self, forKey: .matchCaseNumbers) ?? true
        matchCourts = try container.decodeIfPresent(Bool.self, forKey: .matchCourts) ?? true
        scopedCourtId = try container.decodeIfPresent(String.self, forKey: .scopedCourtId)
        scopedFeedId = try container.decodeIfPresent(String.self, forKey: .scopedFeedId)
        liveActivityEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveActivityEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(term, forKey: .term)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(notifyPush, forKey: .notifyPush)
        try container.encode(isCritical, forKey: .isCritical)
        try container.encode(caseSensitive, forKey: .caseSensitive)
        try container.encode(exactMatch, forKey: .exactMatch)
        try container.encode(selectedStates, forKey: .selectedStates)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(monitoringStartedAt, forKey: .monitoringStartedAt)
        try container.encodeIfPresent(lastCheckedAt, forKey: .lastCheckedAt)
        try container.encode(matchPartyNames, forKey: .matchPartyNames)
        try container.encode(matchCaseNumbers, forKey: .matchCaseNumbers)
        try container.encode(matchCourts, forKey: .matchCourts)
        try container.encodeIfPresent(scopedCourtId, forKey: .scopedCourtId)
        try container.encodeIfPresent(scopedFeedId, forKey: .scopedFeedId)
        try container.encode(liveActivityEnabled, forKey: .liveActivityEnabled)
    }

    static let stateCodes = StateAbbreviations.allCodes

    func acceptsForwardOnlyFiling(pubDate: Date?) -> Bool {
        guard let pubDate else { return false }
        return pubDate >= monitoringStartedAt.addingTimeInterval(-120)
    }
}

struct AddKeywordSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var term: String
    @State private var exactMatch = false
    @State private var caseSensitive = false
    @State private var notifyPush = true
    @State private var isCritical = false
    @State private var selectedStates: Set<String>
    @State private var matchPartyNames = true
    @State private var matchCaseNumbers = true
    @State private var matchCourts = true
    @State private var liveActivityEnabled = true
    @FocusState private var isTermFieldFocused: Bool
    
    private let states = KeywordMonitor.stateCodes
    
    let prefill: AlertKeywordPrefill?
    let onAdd: (KeywordMonitor) -> Void

    init(prefill: AlertKeywordPrefill? = nil, onAdd: @escaping (KeywordMonitor) -> Void) {
        self.prefill = prefill
        self.onAdd = onAdd
        _term = State(initialValue: prefill?.term ?? "")
        _selectedStates = State(initialValue: prefill?.selectedStates ?? [])
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Keyword") {
                    TextField("Enter keyword or phrase", text: $term)
                        .focused($isTermFieldFocused)
                }
                
                Section("Match Options") {
                    Toggle("Exact Match Only", isOn: $exactMatch)
                    Toggle("Case Sensitive", isOn: $caseSensitive)
                    Toggle("Party names", isOn: $matchPartyNames)
                    Toggle("Case numbers", isOn: $matchCaseNumbers)
                    Toggle("Court names", isOn: $matchCourts)
                }
                
                Section {
                    Toggle("Push Notifications", isOn: $notifyPush)
                    Toggle("Priority Alert", isOn: $isCritical)
                        .disabled(!notifyPush)
                    Toggle("Live Activity", isOn: $liveActivityEnabled)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Priority alerts break through Focus modes for time-sensitive notifications. The Live Activity shows this alert's latest results on the Lock Screen and Dynamic Island, with a button to search now.")
                }
                
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(states, id: \.self) { state in
                                Button {
                                    if selectedStates.contains(state) {
                                        selectedStates.remove(state)
                                    } else {
                                        selectedStates.insert(state)
                                    }
                                } label: {
                                    Text(state)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(selectedStates.contains(state) ? .black : .white.opacity(0.7))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .frame(minHeight: 44)
                                        .background(selectedStates.contains(state) ? .white : .white.opacity(0.1), in: Capsule())
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(StateAbbreviations.name(for: state) ?? state)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Filter by State (Optional)")
                } footer: {
                    Text("Leave empty to monitor all states")
                }
                
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.yellow.opacity(0.9))
                            .accessibilityLabel("Warning")
                        Text("Alerts only notify you about new filings that appear after you create the alert. Older cases will not trigger notifications.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } header: {
                    Text("Important")
                }
            }
            .navigationTitle("Add Alert")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isTermFieldFocused = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let keyword = KeywordMonitor(
                            term: trimmed,
                            notifyPush: notifyPush,
                            isCritical: isCritical,
                            caseSensitive: caseSensitive,
                            exactMatch: exactMatch,
                            selectedStates: selectedStates,
                            matchPartyNames: matchPartyNames,
                            matchCaseNumbers: matchCaseNumbers,
                            matchCourts: matchCourts,
                            liveActivityEnabled: liveActivityEnabled
                        )
                        onAdd(keyword)
                        dismiss()
                    }
                    .disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint("Saves the alert and starts checking courts")
                }
            }
        }
    }
}

struct EditKeywordSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var term: String
    @State private var exactMatch: Bool
    @State private var caseSensitive: Bool
    @State private var notifyPush: Bool
    @State private var isCritical: Bool
    @State private var selectedStates: Set<String>
    @State private var matchPartyNames: Bool
    @State private var matchCaseNumbers: Bool
    @State private var matchCourts: Bool
    @State private var liveActivityEnabled: Bool
    @FocusState private var isTermFieldFocused: Bool
    
    private let states = KeywordMonitor.stateCodes
    
    let keyword: KeywordMonitor
    let onSave: (KeywordMonitor) -> Void
    
    init(keyword: KeywordMonitor, onSave: @escaping (KeywordMonitor) -> Void) {
        self.keyword = keyword
        self.onSave = onSave
        _term = State(initialValue: keyword.term)
        _exactMatch = State(initialValue: keyword.exactMatch)
        _caseSensitive = State(initialValue: keyword.caseSensitive)
        _notifyPush = State(initialValue: keyword.notifyPush)
        _isCritical = State(initialValue: keyword.isCritical)
        _selectedStates = State(initialValue: keyword.selectedStates)
        _matchPartyNames = State(initialValue: keyword.matchPartyNames)
        _matchCaseNumbers = State(initialValue: keyword.matchCaseNumbers)
        _matchCourts = State(initialValue: keyword.matchCourts)
        _liveActivityEnabled = State(initialValue: keyword.liveActivityEnabled)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Keyword") {
                    TextField("Enter keyword or phrase", text: $term)
                        .focused($isTermFieldFocused)
                }
                
                Section("Match Options") {
                    Toggle("Exact Match Only", isOn: $exactMatch)
                    Toggle("Case Sensitive", isOn: $caseSensitive)
                    Toggle("Party names", isOn: $matchPartyNames)
                    Toggle("Case numbers", isOn: $matchCaseNumbers)
                    Toggle("Court names", isOn: $matchCourts)
                }
                
                Section {
                    Toggle("Push Notifications", isOn: $notifyPush)
                    Toggle("Priority Alert", isOn: $isCritical)
                        .disabled(!notifyPush)
                    Toggle("Live Activity", isOn: $liveActivityEnabled)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Priority alerts break through Focus modes for time-sensitive notifications. The Live Activity shows this alert's latest results on the Lock Screen and Dynamic Island, with a button to search now.")
                }
                
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(states, id: \.self) { state in
                                Button {
                                    if selectedStates.contains(state) {
                                        selectedStates.remove(state)
                                    } else {
                                        selectedStates.insert(state)
                                    }
                                } label: {
                                    Text(state)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(selectedStates.contains(state) ? .black : .white.opacity(0.7))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .frame(minHeight: 44)
                                        .background(selectedStates.contains(state) ? .white : .white.opacity(0.1), in: Capsule())
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(StateAbbreviations.name(for: state) ?? state)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Filter by State (Optional)")
                } footer: {
                    Text("Leave empty to monitor all states")
                }
            }
            .navigationTitle("Edit Alert")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isTermFieldFocused = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let updatedKeyword = KeywordMonitor(
                            id: keyword.id,
                            term: trimmed,
                            enabled: keyword.enabled,
                            notifyPush: notifyPush,
                            isCritical: isCritical,
                            caseSensitive: caseSensitive,
                            exactMatch: exactMatch,
                            selectedStates: selectedStates,
                            createdAt: keyword.createdAt,
                            monitoringStartedAt: keyword.monitoringStartedAt,
                            lastCheckedAt: keyword.lastCheckedAt,
                            matchPartyNames: matchPartyNames,
                            matchCaseNumbers: matchCaseNumbers,
                            matchCourts: matchCourts,
                            scopedCourtId: keyword.scopedCourtId,
                            scopedFeedId: keyword.scopedFeedId,
                            liveActivityEnabled: liveActivityEnabled
                        )
                        onSave(updatedKeyword)
                        dismiss()
                    }
                    .disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
