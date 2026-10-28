import SwiftUI

struct AlertDetailView: View {
    let keywordId: String

    @Environment(\.dismiss) private var dismiss
    @State private var keyword: KeywordMonitor?
    @State private var stats: KeywordSearchStats?
    @State private var filings: [CaseEntry] = []
    @State private var matches: [CaseMatch] = []
    @State private var hasLoadedFilings = false
    @State private var activeSearch: CaserAlertAttributes.ActiveSearch?
    @State private var isSearching = false
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var caseDetailPresentation: CaseDetailPresentation?

    private var matchByFiling: [String: CaseMatch] {
        Dictionary(matches.map { (Self.filingKey(caseID: $0.caseId, courtID: $0.courtId), $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    private var earlierMatches: [CaseMatch] {
        let current = Set(filings.map { Self.filingKey(caseID: $0.objectID, courtID: $0.courtId) })
        return matches.filter { !current.contains(Self.filingKey(caseID: $0.caseId, courtID: $0.courtId)) }
    }

    var body: some View {
        List {
            if let keyword {
                summarySection(keyword)
                filingsSection(keyword)
                if !earlierMatches.isEmpty {
                    earlierSection
                }
                settingsSection(keyword)
            }
        }
        .listStyle(.insetGrouped)
        .caserListBackground()
        .navigationTitle(keyword?.term ?? "Alert")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
                    .disabled(keyword == nil)
            }
        }
        .refreshable { await search() }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .monitorKeywordSearchDidChange)) { notification in
            guard (notification.object as? String) == nil || (notification.object as? String) == keywordId else { return }
            let wasSearching = isSearching
            refreshSearchState()
            if wasSearching && !isSearching {
                Task { await load() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .monitorScanCompleted)) { _ in
            Task { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .monitorMatchesDidChange)) { _ in
            loadMatches()
        }
        .sheet(isPresented: $isEditing) {
            if let keyword {
                EditKeywordSheet(keyword: keyword) { updated in
                    save(updated)
                }
            }
        }
        .sheet(item: $caseDetailPresentation) { presentation in
            CaseDetailView(entry: presentation.entry, matchedKeyword: presentation.matchedKeyword)
        }
        .confirmationDialog(
            "Delete \u{201C}\(keyword?.term ?? "")\u{201D}?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Alert", role: .destructive) { deleteAlert() }
        } message: {
            Text("CASER will stop checking courts for this term and remove its matches.")
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    private func summarySection(_ keyword: KeywordMonitor) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                if isSearching {
                    searchingSummary
                } else if let stats {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(stats.matchingFilings.formatted()) matching \(stats.matchingFilings == 1 ? "filing" : "filings")")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(stats.matchingFilings > 0 ? Color.caserAccent : .white)
                        Text("Out of \(stats.filingsSearched.formatted()) recent filings in \(stats.courtsSearched.formatted()) \(stats.courtsSearched == 1 ? "court" : "courts") · \(RelativeTime.short(stats.finishedAt))")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text(keyword.enabled ? "Not searched yet" : "This alert is off")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Text(scheduleText(keyword))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))

                if keyword.enabled {
                    Button {
                        Task { await search() }
                    } label: {
                        Label(isSearching ? "Searching…" : "Search Now", systemImage: "magnifyingglass")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.caserAccent)
                    .foregroundStyle(.black)
                    .disabled(isSearching)
                    .accessibilityHint("Checks this alert's courts for filings now")
                }
            }
            .padding(.vertical, 6)
            .caserListRow()
        }
    }

    @ViewBuilder
    private var searchingSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Searching courts…")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            if let activeSearch, activeSearch.courtsTotal > 0 {
                ProgressView(value: activeSearch.fractionComplete)
                    .tint(Color.caserAccent)
                Text("Searched \(activeSearch.courtsSearched) courts · \(activeSearch.filingsSearched.formatted()) filings read")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                ProgressView()
                    .tint(Color.caserAccent)
            }
        }
    }

    @ViewBuilder
    private func filingsSection(_ keyword: KeywordMonitor) -> some View {
        Section {
            if filings.isEmpty {
                Text(emptyFilingsText(keyword))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.vertical, 6)
                    .caserListRow()
            } else {
                ForEach(filings) { filing in
                    let match = matchByFiling[Self.filingKey(caseID: filing.objectID, courtID: filing.courtId)]
                    Button {
                        open(filing, match: match)
                    } label: {
                        CaseRow(
                            item: filing,
                            isUnread: match.map { !$0.read } ?? false,
                            isStarred: match?.starred ?? false,
                            badge: match == nil ? nil : "New"
                        )
                    }
                    .buttonStyle(.plain)
                    .caserListRow()
                }
            }
        } header: {
            CaserSectionHeader(title: "Matching Filings", trailing: filings.isEmpty ? nil : filings.count.formatted())
        } footer: {
            if let stats, stats.matchingFilings > filings.count, !filings.isEmpty {
                Text("Showing the newest \(filings.count.formatted()) of \(stats.matchingFilings.formatted()).")
                    .foregroundStyle(.white.opacity(0.5))
            } else if !filings.isEmpty {
                Text("“New” marks filings that arrived after you created this alert. CASER notifies you only about those.")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var earlierSection: some View {
        Section {
            ForEach(earlierMatches) { match in
                Button {
                    open(match.asCaseEntry(), match: match)
                } label: {
                    CaseRow(item: match, isUnread: !match.read, isStarred: match.starred)
                }
                .buttonStyle(.plain)
                .caserListRow()
            }
        } header: {
            CaserSectionHeader(title: "Earlier Alerts", trailing: earlierMatches.count.formatted())
        } footer: {
            Text("Filings this alert found before that no longer appear in the courts' recent feeds.")
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func settingsSection(_ keyword: KeywordMonitor) -> some View {
        Section {
            Toggle(isOn: Binding(get: { keyword.enabled }, set: { setEnabled($0) })) {
                Label("Alert On", systemImage: "bell")
                    .foregroundStyle(.white)
            }
            .tint(Color.caserAccent)
            .caserListRow()

            LabeledContent {
                Text(CaserLiveActivity.scopeSummary(for: keyword))
                    .foregroundStyle(.white.opacity(0.65))
            } label: {
                Label("Courts", systemImage: "building.columns")
                    .foregroundStyle(.white)
            }
            .caserListRow()

            LabeledContent {
                Text(notificationSummary(keyword))
                    .foregroundStyle(.white.opacity(0.65))
            } label: {
                Label("Notifications", systemImage: "bell.badge")
                    .foregroundStyle(.white)
            }
            .caserListRow()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Alert", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .caserListRow()
        } header: {
            CaserSectionHeader(title: "Alert")
        }
    }

    private func scheduleText(_ keyword: KeywordMonitor) -> String {
        guard keyword.enabled else { return "Turn the alert on to check courts." }
        guard let checked = keyword.lastCheckedAt else { return "Checks every court in scope regularly." }
        let next = MonitorScheduleService.nextScanLabel(lastSyncedAt: checked)
        let nextText = next == "Due now" ? "Next check due now" : next.replacingOccurrences(of: "Next scan", with: "Next check")
        return "All courts checked \(RelativeTime.short(checked)) · \(nextText)"
    }

    private func emptyFilingsText(_ keyword: KeywordMonitor) -> String {
        if !hasLoadedFilings { return "Loading…" }
        if stats == nil { return keyword.enabled ? "Tap Search Now to see filings that mention “\(keyword.term)”." : "Turn the alert on to search courts." }
        if (stats?.matchingFilings ?? 0) > 0 { return "Search again to list these filings." }
        return "No recent filings mention “\(keyword.term)”. Court feeds only carry recent filings, so CASER keeps checking and notifies you when a new one does."
    }

    private func notificationSummary(_ keyword: KeywordMonitor) -> String {
        var parts: [String] = []
        parts.append(keyword.notifyPush ? (keyword.isCritical ? "Priority" : "On") : "Off")
        if keyword.liveActivityEnabled { parts.append("Live Activity") }
        return parts.joined(separator: " · ")
    }

    private static func filingKey(caseID: String, courtID: String) -> String {
        "\(courtID)|\(caseID)"
    }

    private func load() async {
        guard let current = AlertCreationService.shared.loadKeywords().first(where: { $0.id == keywordId }) else {
            keyword = nil
            return
        }
        keyword = current
        stats = KeywordSearchStatsStorage.shared.stats(for: keywordId)
        loadMatches()
        refreshSearchState()
        filings = await Task.detached(priority: .userInitiated) {
            AlertResultsStorage.shared.filings(for: current)
        }.value
        hasLoadedFilings = true
    }

    private func loadMatches() {
        matches = MatchCacheStorage.shared.load()
            .filter { $0.keywordId == keywordId }
            .sorted { ($0.pubDate ?? $0.createdAt) > ($1.pubDate ?? $1.createdAt) }
    }

    private func refreshSearchState() {
        let service = MonitorScanService.shared
        isSearching = service.isSearching(keywordId: keywordId)
        activeSearch = service.activeSearches[keywordId]
    }

    private func search() async {
        guard let keyword, keyword.isSearchable else { return }
        isSearching = true
        await MonitorScanService.shared.searchNow(keywordId: keyword.id)
        refreshSearchState()
        await load()
    }

    private func open(_ filing: CaseEntry, match: CaseMatch?) {
        caseDetailPresentation = CaseDetailPresentation(
            id: filing.id, entry: filing, matchedKeyword: keyword?.term
        )
        guard let match, !match.read else { return }
        MatchCacheStorage.shared.updateMatch(id: match.id) { $0.read = true }
        if let index = matches.firstIndex(where: { $0.id == match.id }) {
            matches[index].read = true
        }
        Task {
            await NotificationManager.shared.syncBadgeFromDelivered()
            await CaserLiveActivity.update(keywordId: keywordId)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        guard let keyword else { return }
        do {
            self.keyword = try AlertCreationService.shared.setAlertEnabled(
                term: keyword.term, keywordID: keyword.id, enabled: enabled
            )
            if enabled { isSearching = true }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(_ updated: KeywordMonitor) {
        do {
            keyword = try AlertCreationService.shared.updateAlert(updated)
            Task { await load() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAlert() {
        do {
            try AlertCreationService.shared.deleteAlert(id: keywordId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
