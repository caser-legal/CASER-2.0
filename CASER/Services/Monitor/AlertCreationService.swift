import Foundation

enum AlertCreationError: LocalizedError {
    case emptyTerm
    case limitReached
    case duplicateTerm
    case keywordNotFound

    var errorDescription: String? {
        switch self {
        case .emptyTerm:
            return "Enter a keyword or phrase to monitor."
        case .limitReached:
            return "You can have up to \(UserSettingsStore.alertLimit) alerts. Delete an alert to add a new one."
        case .duplicateTerm:
            return "You are already monitoring that term."
        case .keywordNotFound:
            return "That alert could not be found."
        }
    }
}

enum AlertToggleResult: Sendable {
    case created(KeywordMonitor)
    case enabled(KeywordMonitor)
    case disabled(KeywordMonitor)
}

struct AlertKeywordPrefill: Sendable {
    var term: String
    var selectedStates: Set<String> = []
}

@MainActor
final class AlertCreationService {
    static let shared = AlertCreationService()

    private let keywordStorage = KeywordMonitorStorage.shared

    func loadKeywords() -> [KeywordMonitor] {
        keywordStorage.load()
    }

    func normalizedTerm(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isDuplicate(_ existing: KeywordMonitor, term: String, scopedCourtId: String?, selectedStates: Set<String>) -> Bool {
        normalizedTerm(existing.term) == normalizedTerm(term)
            && existing.scopedCourtId == scopedCourtId
            && existing.selectedStates == Set(selectedStates.map(StateAbbreviations.canonicalCode(for:)))
    }

    private func searchSoon(_ keyword: KeywordMonitor) {
        Task {
            if keyword.notifyPush {
                await NotificationManager.shared.requestAuthorizationIfNeeded()
            }
            await MonitorScanService.shared.searchNow(keywordId: keyword.id)
        }
    }

    func caseAlert(for entry: CaseEntry, keywords: [KeywordMonitor]? = nil) -> KeywordMonitor? {
        let term = normalizedTerm(caseNumberTerm(for: entry))
        guard !term.isEmpty else { return nil }
        let sameTerm = (keywords ?? keywordStorage.load()).filter { normalizedTerm($0.term) == term }
        if let scoped = sameTerm.first(where: { $0.scopedCourtId == entry.courtId }) {
            return scoped
        }
        return sameTerm.first { $0.scopedCourtId == nil && $0.selectedStates.isEmpty }
    }

    func isCaseAlertOn(for entry: CaseEntry) -> Bool {
        caseAlert(for: entry)?.enabled == true
    }

    @discardableResult
    func setAlertEnabled(
        term: String,
        keywordID: String? = nil,
        enabled: Bool,
        triggerScanOnEnable: Bool = true
    ) throws -> KeywordMonitor {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AlertCreationError.emptyTerm }

        var keywords = try keywordStorage.loadVerified()
        guard let index = keywords.firstIndex(where: {
            if let keywordID { return $0.id == keywordID }
            return normalizedTerm($0.term) == normalizedTerm(term)
        }) else {
            throw AlertCreationError.keywordNotFound
        }

        let wasEnabled = keywords[index].enabled
        keywords[index].enabled = enabled
        if enabled && !wasEnabled {
            keywords[index].monitoringStartedAt = Date()
        }
        try keywordStorage.save(keywords)
        NotificationCenter.default.post(name: .monitorConfigurationDidChange, object: nil)

        if enabled, triggerScanOnEnable {
            searchSoon(keywords[index])
        }

        return keywords[index]
    }

    func toggleAlertForCase(entry: CaseEntry) async throws -> AlertToggleResult {
        if let existing = caseAlert(for: entry) {
            let updated = try setAlertEnabled(term: existing.term, keywordID: existing.id, enabled: !existing.enabled)
            return existing.enabled ? .disabled(updated) : .enabled(updated)
        }
        let keyword = try await createAlert(
            term: caseNumberTerm(for: entry),
            selectedStates: [],
            seedEntry: entry,
            exactMatch: true
        )
        return .created(keyword)
    }

    func caseNumberTerm(for entry: CaseEntry) -> String {
        if let caseNumber = entry.displayCaseNumber?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !caseNumber.isEmpty {
            return caseNumber
        }

        for candidate in [entry.objectID, entry.guid ?? ""] {
            if let extracted = Self.extractCaseNumber(from: candidate) {
                return extracted
            }
        }

        if let extracted = Self.extractCaseNumber(from: entry.title + " " + entry.description) {
            return extracted
        }

        if let party = entry.parties.first?.trimmingCharacters(in: .whitespacesAndNewlines), !party.isEmpty {
            return String(party.prefix(80))
        }

        return String(entry.displayTitle.prefix(80))
    }

    private static func extractCaseNumber(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let patterns = [
            #"(?:No\.|Case)\s*(\d{1,2}:\d{2}-[a-z]{2,3}-\d{4,5})"#,
            #"(?:No\.|#)\s*(\d{2,4}-\d{3,5})"#,
            #"\b(\d{1,2}:\d{2}-[a-z]{2,3}-\d{4,5})\b"#,
            #"\b(\d{2,4}-\d{3,5})\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let range = Range(match.range(at: 1), in: trimmed) else {
                continue
            }
            return String(trimmed[range])
        }
        return nil
    }

    @discardableResult
    func createAlert(
        term: String,
        selectedStates: Set<String> = [],
        seedEntry: CaseEntry? = nil,
        notifyPush: Bool = true,
        isCritical: Bool = false,
        caseSensitive: Bool = false,
        exactMatch: Bool = false,
        matchPartyNames: Bool = true,
        matchCaseNumbers: Bool = true,
        matchCourts: Bool = true,
        liveActivityEnabled: Bool = true
    ) async throws -> KeywordMonitor {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AlertCreationError.emptyTerm }

        var keywords = try keywordStorage.loadVerified()
        guard keywords.count < UserSettingsStore.alertLimit else { throw AlertCreationError.limitReached }

        let duplicate = keywords.contains {
            isDuplicate($0, term: trimmed, scopedCourtId: seedEntry?.courtId, selectedStates: selectedStates)
        }
        guard !duplicate else {
            throw AlertCreationError.duplicateTerm
        }

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
            scopedCourtId: seedEntry?.courtId,
            scopedFeedId: seedEntry?.feedId,
            liveActivityEnabled: liveActivityEnabled
        )
        keywords.append(keyword)
        try keywordStorage.save(keywords)
        NotificationCenter.default.post(name: .monitorConfigurationDidChange, object: nil)

        if notifyPush {
            await NotificationManager.shared.requestAuthorizationIfNeeded()
        }
        searchSoon(keyword)
        return keyword
    }

    func deleteAlert(id: String) throws {
        var keywords = try keywordStorage.loadVerified()
        guard let index = keywords.firstIndex(where: { $0.id == id }) else {
            throw AlertCreationError.keywordNotFound
        }
        let keywordId = keywords[index].id
        keywords.remove(at: index)
        try keywordStorage.save(keywords)
        MatchCacheStorage.shared.removeMatches(forKeywordId: keywordId)
        KeywordSearchStatsStorage.shared.remove(keywordId: keywordId)
        AlertResultsStorage.shared.remove(keywordId: keywordId)
        NotificationCenter.default.post(name: .monitorConfigurationDidChange, object: nil)
        Task {
            let unread = MatchCacheStorage.shared.load().filter { !$0.read }.count
            await NotificationManager.shared.setMonitorBadgeCount(unread)
        }
    }

    @discardableResult
    func updateAlert(_ keyword: KeywordMonitor) throws -> KeywordMonitor {
        let trimmed = keyword.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AlertCreationError.emptyTerm }

        var keywords = try keywordStorage.loadVerified()
        guard let index = keywords.firstIndex(where: { $0.id == keyword.id }) else {
            throw AlertCreationError.keywordNotFound
        }

        if keywords.contains(where: {
            $0.id != keyword.id
                && isDuplicate($0, term: trimmed, scopedCourtId: keyword.scopedCourtId, selectedStates: keyword.selectedStates)
        }) {
            throw AlertCreationError.duplicateTerm
        }

        let previous = keywords[index]
        var updated = keyword
        updated.term = trimmed
        let matchingChanged = previous.matchSignature != updated.matchSignature
            || previous.selectedStates != updated.selectedStates
            || previous.scopedCourtId != updated.scopedCourtId
            || previous.scopedFeedId != updated.scopedFeedId
        if matchingChanged {
            updated.monitoringStartedAt = Date()
            updated.lastCheckedAt = nil
        }
        keywords[index] = updated
        try keywordStorage.save(keywords)
        if matchingChanged {
            KeywordSearchStatsStorage.shared.remove(keywordId: updated.id)
            AlertResultsStorage.shared.remove(keywordId: updated.id)
        }
        NotificationCenter.default.post(name: .monitorConfigurationDidChange, object: nil)

        if updated.isSearchable && (matchingChanged || (!previous.enabled && updated.enabled)) {
            searchSoon(updated)
        } else if !previous.notifyPush && updated.notifyPush {
            Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
        }
        return updated
    }
}
