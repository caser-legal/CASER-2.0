import Foundation

struct FeedTally: Codable, Sendable, Equatable {
    var filings = 0
    var matching = 0

    private enum CodingKeys: String, CodingKey {
        case filings = "f", matching = "m"
    }
}

struct KeywordScanCounts: Sendable, Equatable {
    var filingsSearched = 0
    var matchingFilings = 0
    var newMatches = 0
    var byFeed: [String: FeedTally] = [:]
}

extension KeywordMonitor {
    func covers(feedID: String, stateCode: String?) -> Bool {
        if let scopedFeedId { return feedID == scopedFeedId || feedID == scopedCourtId }
        if let scopedCourtId { return feedID == scopedCourtId }
        guard !selectedStates.isEmpty else { return true }
        guard let stateCode else { return false }
        return selectedStates.contains(stateCode)
    }

    func covers(_ feed: CourtFeed) -> Bool {
        covers(feedID: feed.id, stateCode: StateAbbreviations.canonicalCode(for: feed.state))
    }

    var matchSignature: String {
        [term, "\(caseSensitive)", "\(exactMatch)", "\(matchPartyNames)", "\(matchCaseNumbers)", "\(matchCourts)"]
            .joined(separator: "|")
    }
}

enum MonitorMatchEngine: Sendable {
    static let maxNewFilingAge: TimeInterval = 20 * 24 * 60 * 60
    static let identityRetention: TimeInterval = 21 * 24 * 60 * 60

    static func matchKey(keywordID: String, caseID: String, courtID: String = "") -> String {
        "\(keywordID)-\(courtID)-\(caseID)"
    }

    struct Evaluation: Sendable {
        var matches: [CaseMatch] = []
        var counts: [String: KeywordScanCounts] = [:]
        var identityDates: [String: Date] = [:]
        var matchingEntries: [String: [String: [CaseEntry]]] = [:]
    }

    static func findNewMatches(
        keywords: [KeywordMonitor],
        entries: [CaseEntry],
        existingKeys: Set<String>
    ) -> [CaseMatch] {
        evaluate(keywords: keywords, entries: entries, existingKeys: existingKeys).matches
    }

    static func evaluate(
        keywords: [KeywordMonitor],
        entries: [CaseEntry],
        existingKeys: Set<String>,
        now: Date? = nil
    ) -> Evaluation {
        var result = Evaluation()
        for keyword in keywords { result.counts[keyword.id] = KeywordScanCounts() }
        guard !keywords.isEmpty, !entries.isEmpty else { return result }

        let prepared = entries.map(PreparedEntry.init)
        let cutoff = now.map { $0.addingTimeInterval(-maxNewFilingAge) }
        var seenKeys = existingKeys

        for keyword in keywords {
            guard !Task.isCancelled else { break }
            let matcher = TermMatcher(keyword: keyword)
            var counts = KeywordScanCounts()
            var matching: [String: [CaseEntry]] = [:]

            for item in prepared {
                let entry = item.entry
                guard keyword.covers(feedID: item.feedID, stateCode: item.stateCode) else { continue }
                counts.filingsSearched += 1
                counts.byFeed[item.feedID, default: FeedTally()].filings += 1

                guard matcher.matches(item, keyword: keyword) else { continue }
                counts.matchingFilings += 1
                counts.byFeed[item.feedID, default: FeedTally()].matching += 1
                matching[item.feedID, default: []].append(entry)

                guard keyword.acceptsForwardOnlyFiling(pubDate: entry.pubDate) else { continue }
                if let cutoff, let pubDate = entry.pubDate, pubDate < cutoff { continue }

                let key = matchKey(keywordID: keyword.id, caseID: entry.objectID, courtID: entry.courtId)
                guard seenKeys.insert(key).inserted else { continue }
                counts.newMatches += 1
                result.identityDates[key] = entry.pubDate

                let matchedText = matcher.matchesTitle(item)
                    ? entry.title
                    : String(entry.description.prefix(600))
                result.matches.append(CaseMatch(
                    id: UUID().uuidString,
                    keyword: keyword.term,
                    keywordId: keyword.id,
                    caseId: entry.objectID,
                    courtId: entry.courtId,
                    title: entry.title,
                    matchedText: matchedText,
                    link: entry.link,
                    notified: false,
                    read: false,
                    starred: false,
                    createdAt: Date(),
                    courtName: entry.courtName,
                    caseNumber: entry.displayCaseNumber,
                    citation: nil,
                    documentUrl: entry.primaryDocumentURL,
                    pubDate: entry.pubDate
                ))
            }
            result.counts[keyword.id] = counts
            result.matchingEntries[keyword.id] = matching
        }
        return result
    }

    static func backfillKeywordIds(
        matches: [CaseMatch],
        keywords: [KeywordMonitor]
    ) -> (matches: [CaseMatch], didBackfill: Bool) {
        var result: [CaseMatch] = []
        result.reserveCapacity(matches.count)
        var didBackfill = false

        for match in matches {
            if match.keywordId == nil || (match.keywordId ?? "").isEmpty {
                if let inferredID = keywords.first(where: { $0.term == match.keyword })?.id {
                    let backfilled = CaseMatch(
                        id: match.id,
                        keyword: match.keyword,
                        keywordId: inferredID,
                        caseId: match.caseId,
                        courtId: match.courtId,
                        title: match.title,
                        matchedText: match.matchedText,
                        link: match.link,
                        notified: match.notified,
                        read: match.read,
                        starred: match.starred,
                        createdAt: match.createdAt,
                        courtName: match.courtName,
                        caseNumber: match.caseNumber,
                        citation: match.citation,
                        documentUrl: match.documentUrl,
                        pubDate: match.pubDate
                    )
                    result.append(backfilled)
                    didBackfill = true
                    continue
                }
            }
            result.append(match)
        }

        return (result, didBackfill)
    }

    static func plainText(fromHTML html: String) -> String {
        guard html.contains("<") || html.contains("&") else { return html }
        var scalars = String.UnicodeScalarView()
        var inTag = false
        for scalar in html.unicodeScalars {
            switch scalar {
            case "<":
                inTag = true
            case ">" where inTag:
                inTag = false
                scalars.append(" ")
            default:
                if !inTag { scalars.append(scalar) }
            }
        }
        var text = String(scalars)
        if text.contains("&") {
            for (entity, replacement) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                                          ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")] {
                text = text.replacingOccurrences(of: entity, with: replacement)
            }
        }
        return text
    }
}

private struct PreparedEntry {
    let entry: CaseEntry
    let title: String
    let titleLower: String
    let body: String
    let bodyLower: String
    let parties: String
    let partiesLower: String
    let caseNumber: String
    let caseNumberLower: String
    let court: String
    let courtLower: String
    let stateCode: String?
    let feedID: String

    init(_ entry: CaseEntry) {
        self.entry = entry
        feedID = entry.feedId ?? entry.courtId
        title = entry.title
        titleLower = title.lowercased()
        body = MonitorMatchEngine.plainText(fromHTML: entry.description)
        bodyLower = body.lowercased()
        parties = entry.parties.joined(separator: " ")
        partiesLower = parties.lowercased()
        caseNumber = entry.modsCaseNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        caseNumberLower = caseNumber.lowercased()
        court = entry.courtName ?? ""
        courtLower = court.lowercased()
        stateCode = entry.state.map(StateAbbreviations.canonicalCode(for:))
    }
}

private struct TermMatcher {
    let term: String
    let regex: NSRegularExpression?
    let caseSensitive: Bool

    init(keyword: KeywordMonitor) {
        caseSensitive = keyword.caseSensitive
        term = keyword.caseSensitive ? keyword.term : keyword.term.lowercased()
        if keyword.exactMatch || term.isEmpty {
            regex = nil
        } else {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            let startsWithWord = term.first.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false
            let endsWithWord = term.last.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false
            let pattern = (startsWithWord ? "\\b" : "") + escaped + (endsWithWord ? "\\b" : "")
            regex = try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : .caseInsensitive)
        }
    }

    func matches(_ item: PreparedEntry, keyword: KeywordMonitor) -> Bool {
        if matchesTitle(item) { return true }
        if contains(caseSensitive ? item.body : item.bodyLower) { return true }
        if keyword.matchPartyNames, contains(caseSensitive ? item.parties : item.partiesLower) { return true }
        if keyword.matchCaseNumbers, contains(caseSensitive ? item.caseNumber : item.caseNumberLower) { return true }
        if keyword.matchCourts, contains(caseSensitive ? item.court : item.courtLower) { return true }
        return false
    }

    func matchesTitle(_ item: PreparedEntry) -> Bool {
        contains(caseSensitive ? item.title : item.titleLower)
    }

    private func contains(_ text: String) -> Bool {
        guard !term.isEmpty, !text.isEmpty,
              text.range(of: term, options: .literal) != nil else { return false }
        guard let regex else { return true }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
