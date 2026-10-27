import SwiftUI
import os.log

private let searchLogger = Logger(subsystem: "com.caser.app", category: "SearchView")

struct SearchView: View {
    @State private var searchText = ""
    @State private var selectedStates: Set<String> = []
    @State private var selectedCourtTypes: Set<String> = []
    @State private var selectedDateRange: String = "All time"
    @State private var searchResults: [CaseEntry] = []
    @State private var isSearching = false
    @State private var searchError: String?
    private let searchService = SearchService.shared
    @State private var hasSearched = false
    @Environment(SavingsTrackerStore.self) private var savingsStore
    @Environment(SavedCasesManager.self) private var savedManager
    private let historyManager = SearchHistoryManager.shared
    @State private var currentPage = 1
    @State private var totalFound = 0
    @State private var showFilterSheet = false
    @State private var pdfPreviewItem: PDFPreviewItem?
    @State private var isPreparingPDFExport = false
    @State private var pdfExportError: String?
    @State private var pdfFilterStates: Set<String> = []
    @State private var pdfFilterCourtTypes: Set<String> = []
    @State private var pdfFilterDateRange: String = "All time"
    @State private var caseDetailPresentation: CaseDetailPresentation?
    @State private var recentSearches: [SearchHistoryEntry] = []
    @FocusState private var isSearchFieldFocused: Bool
    
    @State private var searchProgress: Double = 0
    @State private var searchStatusText = ""
    @State private var scannedCourts = 0
    @State private var totalCourtsToScan = 0
    @State private var foundEntries = 0
    @State private var matchingEntries = 0
    @State private var failedCourts = 0
    @State private var completedResultsVisibleCount = PaginatedBatch.pageSize
    
    private let maxQueryLength = 200

    private var visibleCompletedResults: [CaseEntry] {
        PaginatedBatch.page(searchResults, visibleCount: completedResultsVisibleCount)
    }

    private let states = StateAbbreviations.allCodes
    private let courtTypes = SearchCourtFilter.all
    private let dateRanges = ["Last 24 hours", "Last 7 days", "Last 30 days", "Last 90 days", "All time"]
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.6))
                            .accessibilityLabel("Search")
                        TextField("Search cases, parties, courts...", text: $searchText)
                            .foregroundStyle(.white)
                            .tint(.white)
                            .submitLabel(.search)
                            .focused($isSearchFieldFocused)
                            .onChange(of: searchText) { _, newValue in
                                let sanitized = sanitizeQueryForEditing(newValue)
                                guard sanitized == newValue else {
                                    searchText = sanitized
                                    return
                                }
                                handleSearchTextChange(sanitized)
                            }
                            .onSubmit {
                                performSearch(query: searchText)
                            }

                        if !searchText.isEmpty {
                            Button {
                                searchService.cancelSearch()
                                searchText = ""
                                searchResults = []
                                searchError = nil
                                isSearching = false
                                hasSearched = false
                                currentPage = 1
                            } label: {
                                Image(systemName: isSearching ? "stop.circle.fill" : "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white.opacity(0.65))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(isSearching ? "Cancel search" : "Clear search")
                            .accessibilityHint(isSearching ? "Stops the active search and clears the query" : "")
                        }

                        Button {
                            showFilterSheet = true
                        } label: {
                            ZStack {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.title3)
                                    .foregroundStyle(.white.opacity(0.65))
                                if activeFilterCount > 0 {
                                    Circle()
                                        .fill(.blue)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 8, y: -8)
                                        .accessibilityLabel("Filter — \(activeFilterCount) active")
                                }
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel(activeFilterCount > 0 ? "Filter — \(activeFilterCount) active" : "Filter")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassSurface(style: .regular, shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
                    
                    if let searchError {
                        EmptyStateView(
                            icon: "exclamationmark.triangle",
                            title: "Search unavailable",
                            message: searchError
                        )
                    } else if !hasSearched {
                        SearchIdleView(
                            recentSearches: recentSearches,
                            savedCount: savedManager.savedCases.count,
                            onRunSearch: rerun,
                            onDeleteSearch: { entry in
                                historyManager.deleteEntry(entry.id)
                                recentSearches.removeAll { $0.id == entry.id }
                            }
                        )
                    } else if isSearching {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(spacing: 12) {
                                ProgressView(value: searchProgress)
                                    .tint(.white)
                                Text(searchStatusText)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .multilineTextAlignment(.center)
                                HStack {
                                    Spacer()
                                    Text("\(matchingEntries.formatted()) search matches / \(foundEntries.formatted()) filings searched")
                                    Spacer()
                                }
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                            }
                            .padding()
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                            if !searchResults.isEmpty {
                                Text("\(searchResults.count) results so far…")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.horizontal, 4)

                                LazyVStack(spacing: 8) {
                                    ForEach(searchResults) { result in
                                        UnifiedCaseCard(item: result, manager: savedManager, onOpenDetail: { caseDetailPresentation = $0 })
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    } else if searchResults.isEmpty {
                        EmptyStateView(
                            icon: "doc.text.magnifyingglass",
                            title: "No results found",
                            message: "Try different keywords or check spelling"
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(totalFound) results")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                                Spacer()
                                PDFExportTrigger(
                                    label: isPreparingPDFExport ? "Preparing…" : "Export PDF",
                                    isEnabled: !searchResults.isEmpty && !isPreparingPDFExport
                                ) {
                                    Task {
                                        await preparePDFExport()
                                    }
                                }
                            }
                            .padding(.horizontal, 20)

                            LazyVStack(spacing: 8) {
                                ForEach(visibleCompletedResults) { result in
                                    UnifiedCaseCard(item: result, manager: savedManager, onOpenDetail: { caseDetailPresentation = $0 })
                                        .onAppear {
                                            loadMoreCompletedResultsIfNeeded(for: result.id)
                                        }
                                }

                                if PaginatedBatch.canLoadMore(
                                    totalCount: searchResults.count,
                                    visibleCount: completedResultsVisibleCount
                                ) {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .tint(.white.opacity(0.6))
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                            }

                            if searchResults.count > completedResultsVisibleCount {
                                Text("Showing \(completedResultsVisibleCount) of \(searchResults.count) results")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background {
                MainBackground()
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .task {
                async let saved: Void = savedManager.loadSaved()
                recentSearches = await historyManager.loadHistorySummaries()
                await saved
                if searchService.isSearching || !searchService.results.isEmpty {
                    isSearching = searchService.isSearching
                    searchResults = searchService.results
                    hasSearched = true
                    let p = searchService.lastProgress
                    scannedCourts = p.scannedCourts
                    totalCourtsToScan = p.totalCourts
                    foundEntries = p.foundEntries
                    matchingEntries = p.matchingEntries
                    searchProgress = p.progress
                    searchStatusText = p.statusText
                    if !searchService.isSearching, !searchService.results.isEmpty {
                        pdfFilterStates = selectedStates
                        pdfFilterCourtTypes = selectedCourtTypes
                        pdfFilterDateRange = selectedDateRange
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        performSearch(query: searchText)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Search")
                    .disabled(searchText.isEmpty)
                    .opacity(searchText.isEmpty ? 0.55 : 1)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNewSearch)) { _ in
                isSearchFieldFocused = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .performSearch)) { notification in
                if let userInfo = notification.userInfo,
                   let query = userInfo["query"] as? String,
                   let states = userInfo["states"] as? [String] {
                    searchText = query
                    selectedStates = Set(states)
                    if let types = userInfo["courtTypes"] as? [String] {
                        selectedCourtTypes = Set(types).intersection(courtTypes)
                    }
                    if let range = userInfo["dateRange"] as? String, dateRanges.contains(range) {
                        selectedDateRange = range
                    }
                    performSearch(query: query)
                }
            }
            .onDisappear {
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheet(
                    selectedStates: $selectedStates,
                    selectedCourtTypes: $selectedCourtTypes,
                    selectedDateRange: $selectedDateRange,
                    states: states,
                    courtTypes: courtTypes,
                    dateRanges: dateRanges
                )
            }
            .sheet(item: $caseDetailPresentation) { presentation in
                CaseDetailView(
                    entry: presentation.entry,
                    matchedKeyword: presentation.matchedKeyword
                )
            }
            .pdfPreviewSheet(item: $pdfPreviewItem)
            .alert(
                "Export",
                isPresented: Binding(
                    get: { pdfExportError != nil },
                    set: { if !$0 { pdfExportError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { pdfExportError = nil }
            } message: {
                if let pdfExportError { Text(pdfExportError) }
            }
        }
    }
    
    @MainActor
    private func preparePDFExport() async {
        guard !isPreparingPDFExport else { return }
        guard searchResults.count <= PDFExporter.maximumListRows else {
            pdfExportError = "PDF export supports up to \(PDFExporter.maximumListRows.formatted()) results at a time. Narrow the search and try again."
            return
        }

        isPreparingPDFExport = true
        defer { isPreparingPDFExport = false }

        var filters: [String] = []
        if !pdfFilterStates.isEmpty {
            filters.append("States: \(pdfFilterStates.sorted().joined(separator: ", "))")
        }
        if !pdfFilterCourtTypes.isEmpty {
            filters.append("Courts: \(pdfFilterCourtTypes.sorted().joined(separator: ", "))")
        }
        if pdfFilterDateRange != "All time" {
            filters.append("Date: \(pdfFilterDateRange)")
        }
        let resultsSnapshot = searchResults
        let querySnapshot = sanitizeQueryForSubmission(searchText)
        guard let pdfURL = await PDFExporter.exportResults(
            resultsSnapshot,
            query: querySnapshot,
            filters: filters
        ) else {
            if !Task.isCancelled {
                pdfExportError = "Could not create the PDF. Try again or narrow the search."
            }
            return
        }
        guard !Task.isCancelled else {
            try? FileManager.default.removeItem(at: pdfURL)
            return
        }
        pdfPreviewItem = PDFPreviewItem(url: pdfURL, title: "Search Results")
    }

    private func loadMoreCompletedResultsIfNeeded(for resultID: String) {
        guard resultID == visibleCompletedResults.last?.id else { return }
        guard PaginatedBatch.canLoadMore(
            totalCount: searchResults.count,
            visibleCount: completedResultsVisibleCount
        ) else { return }
        completedResultsVisibleCount = PaginatedBatch.nextVisibleCount(
            current: completedResultsVisibleCount,
            totalCount: searchResults.count
        )
    }

    private var activeFilterCount: Int {
        var count = selectedStates.count + selectedCourtTypes.count
        if selectedDateRange != "All time" { count += 1 }
        return count
    }

    private func handleSearchTextChange(_ newValue: String) {
        if isSearching {
            searchResults = []
            searchProgress = 0
            searchStatusText = ""
            scannedCourts = 0
            foundEntries = 0
            matchingEntries = 0
            failedCourts = 0
            hasSearched = false
        }
        searchService.cancelSearch()
        isSearching = false
    }
    
    private func saveSearchActivity(query: String, resultCount: Int, filters: [String], hits: Int, pageSize: Int) async {
        let pagesBilled = SearchFees.billablePagesForSearchRequests(resultCount)
        
        let entry = ActivityEntry(
            type: .search,
            title: "Searched: \(query)",
            description: "\(resultCount) results found",
            searchMetadata: .init(
                query: query,
                filters: filters,
                resultCount: resultCount,
                hits: hits,
                pageSize: pageSize,
                pagesBilled: pagesBilled
            )
        )
        
        var activities = loadLocalActivities()
        activities.insert(entry, at: 0)
        if activities.count > 100 { activities = Array(activities.prefix(100)) }
        saveLocalActivities(activities)
    }
    
    private let activityStorage = SecureFileStore()
    private let activityFile = "local_activity_feed.json"

    private func loadLocalActivities() -> [ActivityEntry] {
        if let data = UserDefaults.standard.data(forKey: "LocalActivityFeed") {
            if let entries = try? JSONDecoder().decode([ActivityEntry].self, from: data) {
                try? activityStorage.save(data, to: activityFile)
                UserDefaults.standard.removeObject(forKey: "LocalActivityFeed")
                return entries
            }
        }
        guard let data = try? activityStorage.load(from: activityFile),
              let entries = try? JSONDecoder().decode([ActivityEntry].self, from: data) else { return [] }
        return entries
    }

    private func saveLocalActivities(_ entries: [ActivityEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            try? activityStorage.save(data, to: activityFile)
        }
    }
    
    @MainActor
    private func performSearch(query: String) {
        let sanitizedQuery = sanitizeQueryForSubmission(query)
        guard !sanitizedQuery.isEmpty else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        hasSearched = true
        isSearching = true
        searchError = nil
        currentPage = 1
        searchProgress = 0
        searchStatusText = "Preparing..."
        scannedCourts = 0
        foundEntries = 0
        matchingEntries = 0
        failedCourts = 0
        searchResults = []
        completedResultsVisibleCount = PaginatedBatch.pageSize
        pdfFilterStates = []
        pdfFilterCourtTypes = []
        pdfFilterDateRange = "All time"

        let activeStates = selectedStates
        let activeCourtTypes = selectedCourtTypes
        let activeDateRange = selectedDateRange

        searchService.performSearch(
            query: sanitizedQuery,
            states: activeStates,
            courtTypes: activeCourtTypes,
            dateRange: activeDateRange
        ) { progress in
                self.scannedCourts = progress.scannedCourts
                self.totalCourtsToScan = progress.totalCourts
                self.foundEntries = progress.foundEntries
                self.matchingEntries = progress.matchingEntries
                self.failedCourts = progress.failedCourts
                self.searchStatusText = progress.statusText
                self.searchProgress = progress.progress

                guard progress.isComplete else {
                    self.searchResults = self.searchService.results
                    return
                }

                self.totalFound = progress.matchingEntries
                self.isSearching = false

                if let error = progress.error {
                    if error != "Search cancelled" {
                        self.searchError = error
                    }
                    self.searchResults = []
                    return
                }

                self.searchResults = self.searchService.results
                self.completedResultsVisibleCount = PaginatedBatch.pageSize
                self.pdfFilterStates = activeStates
                self.pdfFilterCourtTypes = activeCourtTypes
                self.pdfFilterDateRange = activeDateRange

                let totalResultCount = self.searchService.results.count
                let pagesBilled = SearchFees.billablePagesForSearchRequests(totalResultCount)
                let historyEntry = self.historyManager.addEntry(
                    query: sanitizedQuery,
                    states: Array(activeStates),
                    courtTypes: Array(activeCourtTypes),
                    dateRange: activeDateRange,
                    resultCount: totalResultCount,
                    results: self.searchService.results
                )
                self.recentSearches.removeAll {
                    $0.query.caseInsensitiveCompare(sanitizedQuery) == .orderedSame
                        && Set($0.states) == activeStates && Set($0.courtTypes) == activeCourtTypes
                        && $0.dateRange == activeDateRange
                }
                self.recentSearches.insert(historyEntry, at: 0)
                Task {
                    await self.savingsStore.tracker.trackSearch(billableResults: totalResultCount, billablePages: pagesBilled)
                    await self.saveSearchActivity(query: sanitizedQuery, resultCount: totalResultCount, filters: Array(activeStates), hits: totalResultCount, pageSize: totalResultCount)
                }
        }
    }
    
    private func rerun(_ entry: SearchHistoryEntry) {
        searchText = entry.query
        selectedStates = Set(entry.states)
        selectedCourtTypes = Set(entry.courtTypes).intersection(courtTypes)
        selectedDateRange = dateRanges.contains(entry.dateRange) ? entry.dateRange : "All time"
        isSearchFieldFocused = false
        performSearch(query: entry.query)
    }

    private func sanitizeQueryForEditing(_ rawValue: String) -> String {
        var sanitized = rawValue

        sanitized.unicodeScalars.removeAll { CharacterSet.controlCharacters.contains($0) }

        if sanitized.count > maxQueryLength {
            let endIndex = sanitized.index(sanitized.startIndex, offsetBy: maxQueryLength)
            sanitized = String(sanitized[..<endIndex])
        }

        return sanitized
    }

    private func sanitizeQueryForSubmission(_ rawValue: String) -> String {
        sanitizeQueryForEditing(rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct StateFilterBubble: View {
    let state: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(state)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minWidth: 44, minHeight: 44)
                .background(isSelected ? .white : .white.opacity(0.1), in: Capsule())
                .contentShape(Rectangle())
        }
        .accessibilityLabel(StateAbbreviations.name(for: state) ?? state)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct CaseEntry: Codable, Identifiable, CaseDisplayable, Sendable {
    let objectID: String
    let title: String
    let description: String
    let courtId: String
    let courtName: String?
    let courtSlug: String?
    let caseType: String?
    let timezone: String?
    let parties: [String]
    let link: String
    let guid: String?
    let documentLink: String?
    let pubDate: Date?
    let createdAt: Date?
    let state: String?
    let feedId: String?
    let govinfoZipUrl: String?
    let govinfoPdfUrl: String?
    let govinfoModsUrl: String?
    let govinfoPremisUrl: String?
    let govinfoHtmlUrl: String?
    let govinfoSummaryXmlUrl: String?
    let govinfoSummary: String?
    let govinfoContextHtml: String?
    let govinfoCitation: String?
    let modsTitle: String?
    let modsCaseNumber: String?
    let modsSubjects: [String]
    let modsPdfUrls: [String]
    let modsCourtType: String?
    let modsCourtState: String?
    let premisObjectId: String?
    let zipPrimaryPdfPath: String?
    let category: [String]
    let creator: String?
    let source: String?
    
    var matchedKeyword: String? { nil }

    var docketURL: String? { link.trimmedNonEmpty }

    var primaryDocumentURL: String? {
        let docketNormalized = docketURL?.normalizedURLString()
        func differsFromDocket(_ candidate: String?) -> Bool {
            guard let normalized = candidate?.normalizedURLString() else { return false }
            guard let docketNormalized else { return true }
            return normalized != docketNormalized
        }

        if let docLink = documentLink?.trimmedNonEmpty, differsFromDocket(docLink) {
            return docLink
        }
        if let pdfLink = govinfoPdfUrl?.trimmedNonEmpty {
            return pdfLink
        }
        if let zipLink = govinfoZipUrl?.trimmedNonEmpty {
            return zipLink
        }
        if let modsPdf = modsPdfUrls.compactMap({ $0.trimmedNonEmpty }).first {
            return modsPdf
        }
        if let guidURL = guid?.trimmedNonEmpty, guidURL.lowercased().hasPrefix("http") {
            return guidURL
        }
        if let htmlDocument = description.firstHref(matchingSuffixes: ["pdf", "zip", "doc", "docx"]) {
            return htmlDocument
        }
        if let usCourtsDoc = description.firstAnchorURL(where: { url, label in
            guard differsFromDocket(url) else { return false }
            let lowerURL = url.lowercased()
            let docKeywords = ["document", "doc1/", "show_temp", "retrieve", "download", "attachment", "cmecf"]
            if docKeywords.contains(where: { lowerURL.contains($0) }) {
                return true
            }
            let lowerLabel = label.lowercased()
            if lowerLabel.contains("document") || lowerLabel.contains("order") || lowerLabel.contains("motion") {
                return true
            }
            return lowerLabel.range(of: #"\(\d+\)"#, options: .regularExpression) != nil
        }) {
            return usCourtsDoc
        }
        if let anyLink = description.firstHref(matchingSuffixes: nil), differsFromDocket(anyLink) {
            return anyLink
        }
        return docketURL
    }

    var id: String { "\(courtId)|\(objectID)" }

    static let summaryPlaceholder = "Summary unavailable."

    var cleanedSummary: String {
        let sources: [String?] = [
            govinfoSummary,
            govinfoContextHtml,
            description
        ]
        for source in sources {
            guard let text = source?.trimmedNonEmpty else { continue }
            let cleaned = text
                .cleanHTML()
                .removingGovInfoMetadataBlock()
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return CaseEntry.summaryPlaceholder
    }

    var cleanedDescription: String {
        description.cleanHTML()
    }

    var displayCaseNumber: String? {
        if let caseNum = modsCaseNumber?.trimmedNonEmpty {
            return caseNum
        }
        let searchText = title + " " + description
        for regex in CaseEntryPatterns.caseNumber {
            if let match = regex.firstMatch(in: searchText, range: NSRange(searchText.startIndex..., in: searchText)),
               let range = Range(match.range(at: 1), in: searchText) {
                return String(searchText[range])
            }
        }
        return nil
    }

    var displayCitation: String? {
        if let rawCitation = govinfoCitation?.trimmedNonEmpty,
           let cleaned = rawCitation.sanitizedCitationText() {
            return cleaned
        }
        let searchText = title + " " + description
        for regex in CaseEntryPatterns.citation {
            if let match = regex.firstMatch(in: searchText, range: NSRange(searchText.startIndex..., in: searchText)),
               let range = Range(match.range, in: searchText) {
                let candidate = String(searchText[range])
                return candidate.sanitizedCitationText() ?? candidate
            }
        }
        return nil
    }

    var displaySubjects: [String] {
        modsSubjects.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var displayCategories: [String] {
        category.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var primaryDocumentIsZip: Bool {
        guard let url = primaryDocumentURL?.lowercased() else { return false }
        return url.hasSuffix(".zip")
    }

    var displayTitle: String {
        var resolved = (modsTitle?.trimmedNonEmpty ?? title)
            .removingLeadingCaseIdentifier()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = resolved.range(of: #"^[A-Z]{2,}\d{2,}(?:-\d+)?\s+"#, options: .regularExpression) {
            resolved.removeSubrange(range)
        }
        if let range = resolved.range(of: #"^(?:Doc(?:ument)?\s*#?\s*\d+\s*-\s*)"#, options: .regularExpression) {
            resolved.removeSubrange(range)
        }
        return resolved.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated(unsafe) static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter
    }()

    init(
        objectID: String,
        title: String,
        description: String,
        courtId: String,
        courtName: String?,
        courtSlug: String?,
        caseType: String?,
        timezone: String?,
        parties: [String],
        link: String,
        guid: String?,
        documentLink: String?,
        pubDate: Date?,
        createdAt: Date?,
        state: String?,
        feedId: String?,
        govinfoZipUrl: String? = nil,
        govinfoPdfUrl: String? = nil,
        govinfoModsUrl: String? = nil,
        govinfoPremisUrl: String? = nil,
        govinfoHtmlUrl: String? = nil,
        govinfoSummaryXmlUrl: String? = nil,
        govinfoSummary: String? = nil,
        govinfoContextHtml: String? = nil,
        govinfoCitation: String? = nil,
        modsTitle: String? = nil,
        modsCaseNumber: String? = nil,
        modsSubjects: [String] = [],
        modsPdfUrls: [String] = [],
        modsCourtType: String? = nil,
        modsCourtState: String? = nil,
        premisObjectId: String? = nil,
        zipPrimaryPdfPath: String? = nil,
        category: [String] = [],
        creator: String? = nil,
        source: String? = nil
    ) {
        self.objectID = objectID
        self.title = title
        self.description = description
        self.courtId = courtId
        self.courtName = courtName
        self.courtSlug = courtSlug
        self.caseType = caseType
        self.timezone = timezone
        self.parties = parties
        self.link = link
        self.guid = guid
        self.documentLink = documentLink
        self.pubDate = pubDate
        self.createdAt = createdAt
        self.state = state
        self.feedId = feedId
        self.govinfoZipUrl = govinfoZipUrl
        self.govinfoPdfUrl = govinfoPdfUrl
        self.govinfoModsUrl = govinfoModsUrl
        self.govinfoPremisUrl = govinfoPremisUrl
        self.govinfoHtmlUrl = govinfoHtmlUrl
        self.govinfoSummaryXmlUrl = govinfoSummaryXmlUrl
        self.govinfoSummary = govinfoSummary
        self.govinfoContextHtml = govinfoContextHtml
        self.govinfoCitation = govinfoCitation
        self.modsTitle = modsTitle
        self.modsCaseNumber = modsCaseNumber
        self.modsSubjects = modsSubjects
        self.modsPdfUrls = modsPdfUrls
        self.modsCourtType = modsCourtType
        self.modsCourtState = modsCourtState
        self.premisObjectId = premisObjectId
        self.zipPrimaryPdfPath = zipPrimaryPdfPath
        self.category = category
        self.creator = creator
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case objectID
        case title
        case description
        case courtId
        case courtName
        case courtSlug
        case caseType
        case timezone
        case parties
        case link
        case guid
        case documentLink
        case pubDate
        case createdAt
        case state
        case feedId
        case govinfoZipUrl
        case govinfoPdfUrl
        case govinfoModsUrl
        case govinfoPremisUrl
        case govinfoHtmlUrl
        case govinfoSummaryXmlUrl
        case govinfoSummary
        case govinfoContextHtml
        case govinfoCitation
        case modsTitle
        case modsCaseNumber
        case modsSubjects
        case modsPdfUrls
        case modsCourtType
        case modsCourtState
        case premisObjectId
        case zipPrimaryPdfPath
        case category
        case creator
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let objectID = try container.decode(String.self, forKey: .objectID)
        let title = (try? container.decode(String.self, forKey: .title)) ?? ""
        let description = (try? container.decode(String.self, forKey: .description)) ?? ""
        let courtId = (try? container.decode(String.self, forKey: .courtId)) ?? ""
        let courtName = try? container.decode(String.self, forKey: .courtName)
        let courtSlug = try? container.decode(String.self, forKey: .courtSlug)
        let caseType = try? container.decode(String.self, forKey: .caseType)
        let timezone = try? container.decode(String.self, forKey: .timezone)
        let parties = (try? container.decode([String].self, forKey: .parties)) ?? []
        let link = (try? container.decode(String.self, forKey: .link)) ?? ""
        let guid = try? container.decode(String.self, forKey: .guid)
        let documentLink = try? container.decode(String.self, forKey: .documentLink)
        let state = try? container.decode(String.self, forKey: .state)
        let feedId = try? container.decode(String.self, forKey: .feedId)
        let govinfoZipUrl = try? container.decode(String.self, forKey: .govinfoZipUrl)
        let govinfoPdfUrl = try? container.decode(String.self, forKey: .govinfoPdfUrl)
        let govinfoModsUrl = try? container.decode(String.self, forKey: .govinfoModsUrl)
        let govinfoPremisUrl = try? container.decode(String.self, forKey: .govinfoPremisUrl)
        let govinfoHtmlUrl = try? container.decode(String.self, forKey: .govinfoHtmlUrl)
        let govinfoSummaryXmlUrl = try? container.decode(String.self, forKey: .govinfoSummaryXmlUrl)
        let govinfoSummary = try? container.decode(String.self, forKey: .govinfoSummary)
        let govinfoContextHtml = try? container.decode(String.self, forKey: .govinfoContextHtml)
        let govinfoCitation = try? container.decode(String.self, forKey: .govinfoCitation)
        let modsTitle = try? container.decode(String.self, forKey: .modsTitle)
        let modsCaseNumber = try? container.decode(String.self, forKey: .modsCaseNumber)
        let modsSubjects = (try? container.decode([String].self, forKey: .modsSubjects)) ?? []
        let modsPdfUrls = (try? container.decode([String].self, forKey: .modsPdfUrls)) ?? []
        let modsCourtType = try? container.decode(String.self, forKey: .modsCourtType)
        let modsCourtState = try? container.decode(String.self, forKey: .modsCourtState)
        let premisObjectId = try? container.decode(String.self, forKey: .premisObjectId)
        let zipPrimaryPdfPath = try? container.decode(String.self, forKey: .zipPrimaryPdfPath)
        let category = (try? container.decode([String].self, forKey: .category)) ?? []
        let creator = try? container.decode(String.self, forKey: .creator)
        let source = try? container.decode(String.self, forKey: .source)

        let pubDate: Date?
        if let timestampDict = try? container.decode([String: Double].self, forKey: .pubDate),
           let seconds = timestampDict["_seconds"] {
            pubDate = Date(timeIntervalSince1970: seconds)
        } else if let timestamp = try? container.decode(Double.self, forKey: .pubDate) {
            pubDate = Date(timeIntervalSince1970: timestamp)
        } else if let dateString = try? container.decode(String.self, forKey: .pubDate) {
            pubDate = CaseEntry.isoDateFormatter.date(from: dateString)
        } else {
            pubDate = nil
        }

        let createdAt: Date?
        if let createdTimestamp = try? container.decode(Double.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSince1970: createdTimestamp)
        } else {
            createdAt = nil
        }

        self.init(
            objectID: objectID,
            title: title,
            description: description,
            courtId: courtId,
            courtName: courtName,
            courtSlug: courtSlug,
            caseType: caseType,
            timezone: timezone,
            parties: parties,
            link: link,
            guid: guid,
            documentLink: documentLink,
            pubDate: pubDate,
            createdAt: createdAt,
            state: state,
            feedId: feedId,
            govinfoZipUrl: govinfoZipUrl,
            govinfoPdfUrl: govinfoPdfUrl,
            govinfoModsUrl: govinfoModsUrl,
            govinfoPremisUrl: govinfoPremisUrl,
            govinfoHtmlUrl: govinfoHtmlUrl,
            govinfoSummaryXmlUrl: govinfoSummaryXmlUrl,
            govinfoSummary: govinfoSummary,
            govinfoContextHtml: govinfoContextHtml,
            govinfoCitation: govinfoCitation,
            modsTitle: modsTitle,
            modsCaseNumber: modsCaseNumber,
            modsSubjects: modsSubjects,
            modsPdfUrls: modsPdfUrls,
            modsCourtType: modsCourtType,
            modsCourtState: modsCourtState,
            premisObjectId: premisObjectId,
            zipPrimaryPdfPath: zipPrimaryPdfPath,
            category: category,
            creator: creator,
            source: source
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(objectID, forKey: .objectID)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(courtId, forKey: .courtId)
        try container.encodeIfPresent(courtName, forKey: .courtName)
        try container.encodeIfPresent(courtSlug, forKey: .courtSlug)
        try container.encodeIfPresent(caseType, forKey: .caseType)
        try container.encodeIfPresent(timezone, forKey: .timezone)
        try container.encode(parties, forKey: .parties)
        try container.encode(link, forKey: .link)
        try container.encodeIfPresent(guid, forKey: .guid)
        try container.encodeIfPresent(documentLink, forKey: .documentLink)
        try container.encodeIfPresent(state, forKey: .state)
        try container.encodeIfPresent(feedId, forKey: .feedId)
        try container.encodeIfPresent(govinfoZipUrl, forKey: .govinfoZipUrl)
        try container.encodeIfPresent(govinfoPdfUrl, forKey: .govinfoPdfUrl)
        try container.encodeIfPresent(govinfoModsUrl, forKey: .govinfoModsUrl)
        try container.encodeIfPresent(govinfoPremisUrl, forKey: .govinfoPremisUrl)
        try container.encodeIfPresent(govinfoHtmlUrl, forKey: .govinfoHtmlUrl)
        try container.encodeIfPresent(govinfoSummaryXmlUrl, forKey: .govinfoSummaryXmlUrl)
        try container.encodeIfPresent(govinfoSummary, forKey: .govinfoSummary)
        try container.encodeIfPresent(govinfoContextHtml, forKey: .govinfoContextHtml)
        try container.encodeIfPresent(govinfoCitation, forKey: .govinfoCitation)
        try container.encodeIfPresent(modsTitle, forKey: .modsTitle)
        try container.encodeIfPresent(modsCaseNumber, forKey: .modsCaseNumber)
        if !modsSubjects.isEmpty {
            try container.encode(modsSubjects, forKey: .modsSubjects)
        }
        if !modsPdfUrls.isEmpty {
            try container.encode(modsPdfUrls, forKey: .modsPdfUrls)
        }
        try container.encodeIfPresent(modsCourtType, forKey: .modsCourtType)
        try container.encodeIfPresent(modsCourtState, forKey: .modsCourtState)
        try container.encodeIfPresent(premisObjectId, forKey: .premisObjectId)
        try container.encodeIfPresent(zipPrimaryPdfPath, forKey: .zipPrimaryPdfPath)
        if !category.isEmpty {
            try container.encode(category, forKey: .category)
        }
        try container.encodeIfPresent(creator, forKey: .creator)
        try container.encodeIfPresent(source, forKey: .source)

        if let pubDate {
            try container.encode(pubDate.timeIntervalSince1970, forKey: .pubDate)
        }

        if let createdAt {
            try container.encode(createdAt.timeIntervalSince1970, forKey: .createdAt)
        }
    }
}

private struct SearchIdleView: View {
    let recentSearches: [SearchHistoryEntry]
    let savedCount: Int
    let onRunSearch: (SearchHistoryEntry) -> Void
    let onDeleteSearch: (SearchHistoryEntry) -> Void

    private static let recentLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if recentSearches.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.6))
                        .accessibilityHidden(true)
                    Text("Search federal court filings")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Search the latest filings from federal appellate, district, bankruptcy, and national courts by party, company, docket number, or keyword.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.top, 32)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    VStack(spacing: 0) {
                        ForEach(Array(recentSearches.prefix(Self.recentLimit).enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider().overlay(.white.opacity(0.1)).padding(.leading, 48)
                            }
                            Button {
                                onRunSearch(entry)
                            } label: {
                                recentRow(entry)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    onRunSearch(entry)
                                } label: {
                                    Label("Search Again", systemImage: "magnifyingglass")
                                }
                                Button(role: .destructive) {
                                    onDeleteSearch(entry)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            NavigationLink(destination: SavedCasesView()) {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Color.caserAccent)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text("Saved Cases")
                        .font(.body)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(savedCount.formatted())
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Saved Cases, \(savedCount)")
        }
        .padding(.horizontal, 20)
    }

    private func recentRow(_ entry: SearchHistoryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.query)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail(entry))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.left")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Searches again")
    }

    private func detail(_ entry: SearchHistoryEntry) -> String {
        var parts = ["\(entry.resultCount.formatted()) \(entry.resultCount == 1 ? "result" : "results")"]
        if !entry.states.isEmpty {
            let states = entry.states.sorted()
            parts.append(states.count > 3 ? "\(states.prefix(3).joined(separator: ", ")) +\(states.count - 3)" : states.joined(separator: ", "))
        }
        if entry.dateRange != "All time" { parts.append(entry.dateRange) }
        parts.append(RelativeTime.short(entry.timestamp))
        return parts.joined(separator: " · ")
    }
}

struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedStates: Set<String>
    @Binding var selectedCourtTypes: Set<String>
    @Binding var selectedDateRange: String
    let states: [String]
    let courtTypes: [String]
    let dateRanges: [String]
    
    @State private var stagedStates: Set<String> = []
    @State private var stagedCourtTypes: Set<String> = []
    @State private var stagedDateRange: String = "All time"
    @State private var stateSearchText = ""
    @State private var expandedSections: Set<String> = []
    
    private var hasChanges: Bool {
        stagedStates != selectedStates || stagedCourtTypes != selectedCourtTypes || stagedDateRange != selectedDateRange
    }
    
    private var totalSelected: Int {
        stagedStates.count + stagedCourtTypes.count + (stagedDateRange != "All time" ? 1 : 0)
    }
    
    private var filteredStates: [String] {
        if stateSearchText.isEmpty {
            return states
        }
        return states.filter { $0.localizedCaseInsensitiveContains(stateSearchText) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        FilterSection(
                            title: "Court Type",
                            count: stagedCourtTypes.count,
                            isExpanded: expandedSections.contains("Court Type")
                        ) {
                            toggleSection("Court Type")
                        } content: {
                            VStack(spacing: 0) {
                                ForEach(courtTypes, id: \.self) { type in
                                    FilterRow(
                                        title: type,
                                        isSelected: stagedCourtTypes.contains(type)
                                    ) {
                                        if stagedCourtTypes.contains(type) {
                                            stagedCourtTypes.remove(type)
                                        } else {
                                            stagedCourtTypes.insert(type)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                        
                        FilterSection(
                            title: "Date Range",
                            count: stagedDateRange != "All time" ? 1 : 0,
                            isExpanded: expandedSections.contains("Date Range")
                        ) {
                            toggleSection("Date Range")
                        } content: {
                            VStack(spacing: 0) {
                                ForEach(dateRanges, id: \.self) { range in
                                    FilterRow(
                                        title: range,
                                        isSelected: stagedDateRange == range
                                    ) {
                                        stagedDateRange = range
                                    }
                                }
                            }
                        }
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                        
                        FilterSection(
                            title: "State",
                            count: stagedStates.count,
                            isExpanded: expandedSections.contains("State")
                        ) {
                            toggleSection("State")
                        } content: {
                            VStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.white.opacity(0.5))
                                        .font(.caption)
                                    TextField("Search states", text: $stateSearchText)
                                        .foregroundStyle(.white)
                                        .font(.subheadline)
                                    if !stateSearchText.isEmpty {
                                        Button {
                                            stateSearchText = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white.opacity(0.5))
                                                .font(.caption)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                
                                if states.count > 10 {
                                    HStack(spacing: 16) {
                                        Button("Select All") {
                                            stagedStates = Set(filteredStates)
                                        }
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.blue)
                                        
                                        Button("Clear") {
                                            stagedStates.removeAll()
                                        }
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.blue)
                                    }
                                    .padding(.horizontal, 16)
                                }
                                
                                VStack(spacing: 0) {
                                    if filteredStates.isEmpty {
                                        Text("No states match")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .padding(.vertical, 20)
                                    } else {
                                        ForEach(filteredStates, id: \.self) { state in
                                            FilterRow(
                                                title: state,
                                                isSelected: stagedStates.contains(state)
                                            ) {
                                                if stagedStates.contains(state) {
                                                    stagedStates.remove(state)
                                                } else {
                                                    stagedStates.insert(state)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.bottom, 80)
                }
                
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.white.opacity(0.2))
                    
                    HStack {
                        Button("Reset") {
                            stagedStates.removeAll()
                            stagedCourtTypes.removeAll()
                            stagedDateRange = "All time"
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        
                        Spacer()
                        
                        Text("\(totalSelected) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button("Apply") {
                            selectedStates = stagedStates
                            selectedCourtTypes = stagedCourtTypes
                            selectedDateRange = stagedDateRange
                            dismiss()
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(hasChanges ? .blue : .secondary)
                        .disabled(!hasChanges)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(white: 0.1))
                }
            }
            .background(Color(white: 0.1))
            .navigationTitle("Filters (\(totalSelected))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            stagedStates = selectedStates
            stagedCourtTypes = selectedCourtTypes
            stagedDateRange = selectedDateRange
            expandedSections = ["State"]
        }
    }
    
    private func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }
}

struct FilterSection<Content: View>: View {
    let title: String
    let count: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                content
            }
        }
    }
}

struct FilterRow: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.white)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.blue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}


private enum CaseEntryPatterns {
    static let caseNumber: [NSRegularExpression] = compile([
        #"(?:No\.|Case)\s*(\d{1,2}:\d{2}-[a-z]{2,3}-\d{4,5})"#,
        #"(?:No\.|#)\s*(\d{2,4}-\d{3,5})"#,
        #"\b(\d{1,2}:\d{2}-[a-z]{2,3}-\d{4,5})\b"#
    ])

    static let citation: [NSRegularExpression] = compile([
        #"\b(\d{1,4}\s+F\.\s*(?:2d|3d|4th|Supp\.|App'x)\s+\d{1,4})\b"#,
        #"\b(\d{1,4}\s+U\.S\.\s+\d{1,4})\b"#,
        #"\b(\d{1,4}\s+S\.\s*Ct\.\s+\d{1,4})\b"#
    ])

    private static func compile(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }
}
