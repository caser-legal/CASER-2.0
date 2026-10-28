import Foundation
import os.log

private let searchServiceLogger = Logger(subsystem: "com.caser.app", category: "SearchService")

struct SearchProgress: Sendable {
    let scannedCourts: Int
    let totalCourts: Int
    let foundEntries: Int
    let matchingEntries: Int
    let failedCourts: Int
    let statusText: String
    let progress: Double
    let isComplete: Bool
    let error: String?
}

enum SearchCourtFilter {
    static let all = ["Appellate", "District", "Bankruptcy", "National"]

    static func includes(_ feed: CourtFeed, in selection: Set<String>) -> Bool {
        let selection = selection.intersection(all)
        guard !selection.isEmpty else { return true }
        let isNational = feed.state == "National" && feed.type != .appellate
        return selection.contains { type in
            switch type {
            case "Appellate": feed.type == .appellate
            case "District": feed.type == .district && !isNational
            case "Bankruptcy": feed.type == .bankruptcy
            case "National": isNational
            default: false
            }
        }
    }
}

struct DetectedCaseReference: Equatable, Sendable {
    let original: String
    let shortYear: String
    let fullYear: String
    let caseType: String
    let number: String
    let suffix: String?

    var canonicalShort: String {
        [shortYear, caseType, number, suffix].compactMap { $0 }.joined(separator: "-")
    }

    var canonicalPadded: String {
        let padded = String(repeating: "0", count: max(0, 5 - number.count)) + number
        return [fullYear, caseType, padded, suffix].compactMap { $0 }.joined(separator: "-")
    }

    var searchVariants: [String] {
        let padded = String(repeating: "0", count: max(0, 5 - number.count)) + number
        var variants = [
            original,
            canonicalShort,
            canonicalPadded,
            [shortYear, caseType, padded, suffix].compactMap { $0 }.joined(separator: "-"),
            canonicalShort.replacingOccurrences(of: "-", with: " "),
            canonicalPadded.replacingOccurrences(of: "-", with: ""),
            "\(caseType) \(number) \(suffix ?? "")".trimmingCharacters(in: .whitespaces),
            "\(shortYear)-\(caseType)-\(number)",
            "\(shortYear)-\(caseType)-\(padded)"
        ]
        var seen = Set<String>()
        variants = variants.filter { seen.insert($0.lowercased()).inserted }
        return variants
    }
}

enum CaseReferenceSearchTerms {
    private static let expression: NSRegularExpression? = {
        let pattern = #"(?i)\b((?:19|20)?\d{2})[\s:._/\-]*(cv|cr|mc|bk|ap|mj)[\s:._/\-]*0*(\d{1,7})(?:[\s:._/\-]*([a-z]{2,6}(?:[\s._/\-]+[a-z]{2,6})?))?\b"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    static func detect(in text: String) -> [DetectedCaseReference] {
        guard let expression else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let whole = Range(match.range(at: 0), in: text),
                  let yearRange = Range(match.range(at: 1), in: text),
                  let typeRange = Range(match.range(at: 2), in: text),
                  let numberRange = Range(match.range(at: 3), in: text) else { return nil }

            let rawYear = String(text[yearRange])
            let fullYear = rawYear.count == 2 ? "20\(rawYear)" : rawYear
            let rawSuffix: String? = {
                guard match.range(at: 4).location != NSNotFound,
                      let suffixRange = Range(match.range(at: 4), in: text) else { return nil }
                return String(text[suffixRange])
                    .replacingOccurrences(of: #"[\s._/]+"#, with: "-", options: .regularExpression)
                    .uppercased()
            }()

            return DetectedCaseReference(
                original: String(text[whole]),
                shortYear: String(fullYear.suffix(2)),
                fullYear: fullYear,
                caseType: String(text[typeRange]).lowercased(),
                number: String(Int(String(text[numberRange])) ?? 0),
                suffix: rawSuffix
            )
        }
    }

    static func localSearchTerms(for query: String) -> [String] {
        let references = detect(in: query)
        guard !references.isEmpty else {
            return [query.lowercased()]
        }
        var seen = Set<String>()
        return ([query] + references.flatMap(\.searchVariants))
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func compactSearchKey(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }
}

struct SearchQueryMatcher: Sendable {
    private let terms: [String]
    private let compactTerms: [String]
    private let cutoff: Date?

    init(query: String, dateRange: String, now: Date = Date()) {
        terms = CaseReferenceSearchTerms.localSearchTerms(for: query)
        compactTerms = terms.compactMap { term in
            let compact = CaseReferenceSearchTerms.compactSearchKey(term)
            return compact.isEmpty || compact == term ? nil : compact
        }
        let days: Int? = switch dateRange {
        case "Last 24 hours": 1
        case "Last 7 days": 7
        case "Last 30 days": 30
        case "Last 90 days": 90
        default: nil
        }
        cutoff = days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: now) }
    }

    func matches(_ entry: CaseEntry) -> Bool {
        if let cutoff, (entry.pubDate ?? .distantPast) < cutoff { return false }
        let searchable = "\(entry.title) \(entry.description) \(entry.courtName ?? "") \(entry.objectID)".lowercased()
        if terms.contains(where: { searchable.contains($0) }) { return true }
        guard !compactTerms.isEmpty else { return false }
        let compact = CaseReferenceSearchTerms.compactSearchKey(searchable)
        return compactTerms.contains { compact.contains($0) }
    }
}

@MainActor
final class SearchService {
    static let shared = SearchService()

    private var searchTask: Task<Void, Never>?
    private var activeSearchID: UUID?

    private static let maxConcurrentCourts = 32
    private static let livePublicationInterval: Duration = .milliseconds(150)

    private(set) var lastProgress = SearchProgress(
        scannedCourts: 0, totalCourts: 0, foundEntries: 0,
        matchingEntries: 0, failedCourts: 0, statusText: "",
        progress: 0, isComplete: false, error: nil
    )

    private(set) var results: [CaseEntry] = []
    private(set) var isSearching = false

    private let rssService = LocalRSSService.shared
    private let feedManager = CourtFeedManager.shared

    private init() {
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: caches.appendingPathComponent("local_scan_cache.json"))
        }
    }

    func performSearch(
        query: String,
        states: Set<String>,
        courtTypes: Set<String>,
        dateRange: String,
        onProgress: @escaping @MainActor @Sendable (SearchProgress) -> Void
    ) {
        searchTask?.cancel()
        let searchID = UUID()
        activeSearchID = searchID
        isSearching = true
        results = []

        let sanitized = String(
            query.trimmingCharacters(in: .whitespacesAndNewlines)
                .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
                .prefix(200)
        )
        let matcher = SearchQueryMatcher(query: sanitized, dateRange: dateRange)
        let feeds = feedManager.feedsWithValidURLs.filter { feed in
            (states.isEmpty || states.contains(feed.stateAbbreviation))
                && SearchCourtFilter.includes(feed, in: courtTypes)
        }

        let archiveDays: Int? = switch dateRange {
        case "Last 24 hours": 1
        case "Last 7 days": 7
        case "Last 90 days": 30
        default: 30
        }
        searchTask = Task { [weak self] in
            await self?.run(
                searchID: searchID,
                feeds: feeds,
                matcher: matcher,
                archiveQuery: sanitized,
                archiveDays: archiveDays,
                states: states,
                courtTypes: courtTypes,
                onProgress: onProgress
            )
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        activeSearchID = nil
        isSearching = false
    }

    private struct CourtResult: Sendable {
        let filings: Int
        let matches: [CaseEntry]
        let failed: Bool
    }

    private func run(
        searchID: UUID,
        feeds: [CourtFeed],
        matcher: SearchQueryMatcher,
        archiveQuery: String = "",
        archiveDays: Int? = nil,
        states: Set<String> = [],
        courtTypes: Set<String> = [],
        onProgress: @escaping @MainActor @Sendable (SearchProgress) -> Void
    ) async {
        // Past filings: the server archive holds 30 days of every court feed and
        // refreshes every 12 hours, while live feeds only carry recent entries.
        let archiveTask = Task { () -> [CaseEntry] in
            guard let archiveDays, !archiveQuery.isEmpty else { return [] }
            let entries = await FeedArchiveClient.shared.search(query: archiveQuery, days: archiveDays)
            return entries.filter { entry in
                guard matcher.matches(entry) else { return false }
                if !states.isEmpty {
                    guard let state = entry.state else { return false }
                    let feedState = CourtFeedManager.shared.feedsWithValidURLs.first { $0.id == entry.courtId }?.stateAbbreviation
                    guard states.contains(state) || (feedState.map { states.contains($0) } ?? false) else { return false }
                }
                return true
            }
        }
        defer { archiveTask.cancel() }
        let total = feeds.count
        guard total > 0 else {
            finish(searchID: searchID, progress: SearchProgress(
                scannedCourts: 0, totalCourts: 0, foundEntries: 0, matchingEntries: 0, failedCourts: 0,
                statusText: "No courts match the selected filters", progress: 1, isComplete: true,
                error: "No courts match the selected filters"
            ), onProgress: onProgress)
            return
        }

        publish(SearchProgress(
            scannedCourts: 0, totalCourts: total, foundEntries: 0, matchingEntries: 0, failedCourts: 0,
            statusText: "Searching \(total) courts…", progress: 0, isComplete: false, error: nil
        ), onProgress: onProgress)

        let rss = rssService
        var scanned = 0
        var failed = 0
        var filings = 0
        var pending: [CaseEntry] = []
        var seenIDs = Set<String>()
        var lastPublished = ContinuousClock.now
        let startedAt = ContinuousClock.now

        await withTaskGroup(of: CourtResult.self) { group in
            var next = 0
            func enqueue() {
                guard next < feeds.count else { return }
                let court = feeds[next]
                next += 1
                group.addTask {
                    await Self.search(court, matcher: matcher, rss: rss)
                }
            }
            for _ in 0..<min(Self.maxConcurrentCourts, feeds.count) { enqueue() }

            for await result in group {
                guard !Task.isCancelled, activeSearchID == searchID else {
                    group.cancelAll()
                    return
                }
                enqueue()
                scanned += 1
                filings += result.filings
                if result.failed { failed += 1 }
                for entry in result.matches where seenIDs.insert(entry.id).inserted {
                    pending.append(entry)
                }

                let now = ContinuousClock.now
                guard scanned < total, now - lastPublished >= Self.livePublicationInterval else { continue }
                lastPublished = now
                mergePending(&pending)
                publish(SearchProgress(
                    scannedCourts: scanned, totalCourts: total, foundEntries: filings,
                    matchingEntries: results.count, failedCourts: failed,
                    statusText: "Searched \(scanned) courts",
                    progress: Double(scanned) / Double(total), isComplete: false, error: nil
                ), onProgress: onProgress)
            }
        }

        guard !Task.isCancelled, activeSearchID == searchID else { return }
        mergePending(&pending)
        let archived = await archiveTask.value
        if !archived.isEmpty {
            var known = Set(results.map(\.id))
            let fresh = archived.filter { known.insert($0.id).inserted }
            if !fresh.isEmpty {
                results = Self.sortedNewestFirst(results + fresh)
            }
        }
        let elapsed = ContinuousClock.now - startedAt
        searchServiceLogger.info("Search finished in \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds]))): \(scanned - failed)/\(total) courts, \(filings) filings, \(self.results.count) matches")

        let nothingLoaded = failed == total
        let count = results.count
        finish(searchID: searchID, progress: SearchProgress(
            scannedCourts: total, totalCourts: total, foundEntries: filings,
            matchingEntries: count, failedCourts: failed,
            statusText: nothingLoaded ? "Unable to load court filings right now" : "Done — \(count) result\(count == 1 ? "" : "s")",
            progress: 1, isComplete: true,
            error: nothingLoaded ? "Unable to load court filings right now" : nil
        ), onProgress: onProgress)
    }

    nonisolated private static func search(_ court: CourtFeed, matcher: SearchQueryMatcher, rss: LocalRSSService) async -> CourtResult {
        do {
            let items = try await rss.fetchFeed(from: court.url)
            var matches: [CaseEntry] = []
            for item in items {
                let entry = rss.mapToCaseEntry(item, court: court)
                if matcher.matches(entry) { matches.append(entry) }
            }
            return CourtResult(filings: items.count, matches: matches, failed: false)
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                searchServiceLogger.debug("Court \(court.id) unavailable: \(error.localizedDescription)")
            }
            return CourtResult(filings: 0, matches: [], failed: true)
        }
    }

    private func mergePending(_ pending: inout [CaseEntry]) {
        guard !pending.isEmpty else { return }
        results = Self.sortedNewestFirst(results + pending)
        pending.removeAll(keepingCapacity: true)
    }

    private func publish(_ progress: SearchProgress, onProgress: @MainActor @Sendable (SearchProgress) -> Void) {
        lastProgress = progress
        onProgress(progress)
    }

    private func finish(searchID: UUID, progress: SearchProgress, onProgress: @MainActor @Sendable (SearchProgress) -> Void) {
        guard activeSearchID == searchID else { return }
        isSearching = false
        activeSearchID = nil
        searchTask = nil
        publish(progress, onProgress: onProgress)
    }

    private static func sortedNewestFirst(_ entries: [CaseEntry]) -> [CaseEntry] {
        entries.sorted { lhs, rhs in
            switch (lhs.pubDate, rhs.pubDate) {
            case let (l?, r?): l > r
            case (_?, nil): true
            default: false
            }
        }
    }
}
