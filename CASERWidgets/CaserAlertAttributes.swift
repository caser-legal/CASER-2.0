import ActivityKit
import Foundation

struct CaserAlertAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var lastCheckedAt: Date?
        var newFilingCount: Int
        var latestFilingTitle: String?
        var latestFilingAt: Date?
        var nextCheckAt: Date
        var latestFilingCourt: String?
        var unreadCount: Int?
        var lastSearch: LastSearch?
        var activeSearch: ActiveSearch?

        var hasNewFiling: Bool { newFilingCount > 0 }
        var isSearching: Bool { activeSearch != nil }
    }

    struct LastSearch: Codable, Hashable {
        var finishedAt: Date
        var matchingFilings: Int
        var filingsSearched: Int
        var newMatches: Int
        var courtsSearched: Int
        var courtsTotal: Int
        var courtsFailed: Int
        var wasOnDemand: Bool
    }

    struct ActiveSearch: Codable, Hashable {
        var startedAt: Date
        var courtsSearched: Int
        var courtsTotal: Int
        var filingsSearched: Int

        var fractionComplete: Double {
            guard courtsTotal > 0 else { return 0 }
            return min(1, Double(courtsSearched) / Double(courtsTotal))
        }
    }

    var keywordId: String
    var term: String
    var alertSetAt: Date
    var scopeSummary: String?
}

enum CaserDeepLink {
    static let scheme = "caser"

    static func alertURL(keywordId: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "alerts"
        components.queryItems = [URLQueryItem(name: "keyword", value: keywordId)]
        return components.url ?? URL(string: "\(scheme)://alerts")!
    }

    static func alertKeywordId(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "alerts" else { return nil }
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "keyword" }?.value
        return id ?? ""
    }
}
