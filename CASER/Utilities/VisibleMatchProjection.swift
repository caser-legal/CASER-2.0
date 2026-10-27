import Foundation

enum VisibleMatchProjection {
    static func filter(_ matches: [CaseMatch], keywords: [KeywordMonitor]) -> [CaseMatch] {
        var keywordById: [String: KeywordMonitor] = [:]
        for keyword in keywords {
            keywordById[keyword.id] = keyword
        }
        return matches.filter { match in
            guard let keywordId = match.keywordId,
                  let keyword = keywordById[keywordId] else { return false }
            return keyword.acceptsForwardOnlyFiling(pubDate: match.pubDate)
        }
    }

    static func count(matches: [CaseMatch], keywords: [KeywordMonitor]) -> Int {
        filter(matches, keywords: keywords).count
    }

    static func loadVisible() -> [CaseMatch] {
        let keywords = KeywordMonitorStorage.shared.load()
        return filter(MatchCacheStorage.shared.load(), keywords: keywords)
    }

    static func visibleCount() -> Int {
        loadVisible().count
    }
}
