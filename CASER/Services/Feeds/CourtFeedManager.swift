import Foundation
import os.log

enum CourtType: String, Codable, CaseIterable, Sendable {
    case district
    case bankruptcy
    case appellate
}

enum FeedSource: String, Codable, Sendable {
    case uscourts
    case govinfo
}

struct CourtFeed: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let state: String
    let type: CourtType
    let timezone: String
    let url: URL
    let source: FeedSource

    var stateAbbreviation: String {
        StateAbbreviations.abbreviation(for: state) ?? state
    }
}

@MainActor
class CourtFeedManager {
    static let shared = CourtFeedManager()

    nonisolated static func isTrustedFeedHost(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        let lower = host.lowercased()
        return lower == "uscourts.gov" || lower.hasSuffix(".uscourts.gov")
            || lower == "govinfo.gov" || lower.hasSuffix(".govinfo.gov")
    }
    
    private(set) var allFeeds: [CourtFeed] = []
    private var cachedAllStates: [String]?
    
    private init() {
        loadFeeds()
    }
    
    func loadFeeds() {
        var feeds: [CourtFeed] = []
        feeds.append(contentsOf: loadUSCourtsFeeds())
        feeds.append(contentsOf: loadGovInfoFeeds())
        allFeeds = feeds
        cachedAllStates = nil
    }
    
    var feedsWithValidURLs: [CourtFeed] {
        allFeeds.filter { Self.isTrustedFeedHost($0.url) }
    }
    
    func feeds(forState state: String) -> [CourtFeed] {
        allFeeds.filter { $0.state == state || $0.stateAbbreviation == state }
    }
    
    func feeds(ofType type: CourtType) -> [CourtFeed] {
        allFeeds.filter { $0.type == type }
    }
    
    func feeds(forStates states: Set<String>, types: Set<CourtType>? = nil) -> [CourtFeed] {
        allFeeds.filter { feed in
            let stateMatch = states.isEmpty || states.contains(feed.state) || states.contains(feed.stateAbbreviation)
            let typeMatch: Bool
            if let types = types {
                typeMatch = types.isEmpty || types.contains(feed.type)
            } else {
                typeMatch = true
            }
            return stateMatch && typeMatch
        }
    }
    
    var allStates: [String] {
        if let cachedAllStates {
            return cachedAllStates
        }
        let states = Array(Set(allFeeds.map { $0.state })).sorted()
        cachedAllStates = states
        return states
    }
    
    private func loadUSCourtsFeeds() -> [CourtFeed] {
        guard let url = Bundle.main.url(forResource: "uscourts-rss-feed-list", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        
        struct USCourtEntry: Decodable {
            let name: String
            let state: String
            let type: String
            let timezone: String
            let url: String?
        }
        
        guard let entries = try? JSONDecoder().decode([USCourtEntry].self, from: data) else { return [] }
        
        var skippedHTTPCount = 0
        
        let feeds = entries.compactMap { entry -> CourtFeed? in
            guard let urlString = entry.url, let feedURL = URL(string: urlString) else { return nil }
            
            guard feedURL.scheme?.lowercased() == "https" else {
                skippedHTTPCount += 1
                os_log("Skipping insecure HTTP feed: %{public}@ - %{public}@", 
                       log: .default, type: .error, entry.name, urlString)
                return nil
            }

            guard Self.isTrustedFeedHost(feedURL) else {
                os_log("Skipping untrusted feed host: %{public}@ - %{public}@",
                       log: .default, type: .error, entry.name, urlString)
                return nil
            }
            
            let courtType: CourtType = switch entry.type {
            case "appellate": .appellate
            case "bankruptcy": .bankruptcy
            default: .district
            }
            return CourtFeed(
                id: "uscourts-\(entry.name.lowercased().replacingOccurrences(of: " ", with: "-"))",
                name: entry.name,
                state: entry.state,
                type: courtType,
                timezone: entry.timezone,
                url: feedURL,
                source: .uscourts
            )
        }
        
        if skippedHTTPCount > 0 {
            os_log("Security: Skipped %{public}d HTTP feed(s). Only HTTPS feeds are supported.", 
                   log: .default, type: .fault, skippedHTTPCount)
        }
        
        return feeds
    }
    
    private func loadGovInfoFeeds() -> [CourtFeed] {
        guard let url = Bundle.main.url(forResource: "govinfo-rss-feed-list", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        
        var feeds: [CourtFeed] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            guard line.contains("uscourts-") else { continue }
            guard let urlMatch = line.range(of: "https://[^\\s]+", options: .regularExpression),
                  let feedURL = URL(string: String(line[urlMatch])) else { continue }
            
            guard feedURL.scheme?.lowercased() == "https" else {
                os_log("Skipping insecure HTTP feed in govinfo: %{public}@", 
                       log: .default, type: .error, feedURL.absoluteString)
                continue
            }

            guard Self.isTrustedFeedHost(feedURL) else {
                os_log("Skipping untrusted govinfo feed host: %{public}@",
                       log: .default, type: .error, feedURL.absoluteString)
                continue
            }
            
            let urlString = feedURL.absoluteString
            guard let courtCode = urlString.components(separatedBy: "uscourts-").last?.replacingOccurrences(of: ".xml", with: "") else { continue }
            
            let (name, state, type) = parseCourtCode(courtCode)
            
            feeds.append(CourtFeed(
                id: "govinfo-\(courtCode)",
                name: name,
                state: state,
                type: type,
                timezone: timezoneForState(state),
                url: feedURL,
                source: .govinfo
            ))
        }
        
        return feeds
    }
    
    private func parseCourtCode(_ code: String) -> (name: String, state: String, type: CourtType) {
        let districtMap: [String: String] = [
            "n": "Northern", "s": "Southern", "e": "Eastern", "w": "Western",
            "m": "Middle", "c": "Central"
        ]
        
        switch code {
        case "jpml": return ("Judicial Panel on Multidistrict Litigation", "National", .district)
        case "cit": return ("U.S. Court of International Trade", "National", .district)
        case "cofc": return ("U.S. Court of Federal Claims", "National", .district)
        case "nmid": return ("Northern Mariana Islands District Court", "Northern Mariana Islands", .district)
        case "nmib": return ("Northern Mariana Islands Bankruptcy Court", "Northern Mariana Islands", .bankruptcy)
        default: break
        }

        if code.hasPrefix("ca") && code.count <= 4 {
            let circuit = String(code.dropFirst(2))
            let circuitName = switch circuit {
            case "dc": "D.C. Circuit"
            case "fc", "13": "Federal Circuit"
            case "1": "First Circuit"
            case "2": "Second Circuit"
            case "3": "Third Circuit"
            default: "\(circuit)th Circuit"
            }
            return ("U.S. Court of Appeals for the \(circuitName)", "National", .appellate)
        }
        
        if code.hasSuffix("b") {
            let stateCode = String(code.dropLast())
            var district = ""
            var stateKey = stateCode

            for (suffix, name) in districtMap {
                if stateCode.hasSuffix(suffix) && stateCode.count > 2 {
                    district = name + " "
                    stateKey = String(stateCode.dropLast())
                    break
                }
            }

            let state = StateAbbreviations.name(for: stateKey) ?? stateKey.uppercased()
            return ("\(state) \(district)Bankruptcy Court", state, .bankruptcy)
        }

        if code.hasSuffix("d") {
            let stateCode = String(code.dropLast())
            var district = ""
            var stateKey = stateCode

            for (suffix, name) in districtMap {
                if stateCode.hasSuffix(suffix) && stateCode.count > 2 {
                    district = name + " "
                    stateKey = String(stateCode.dropLast())
                    break
                }
            }

            let state = StateAbbreviations.name(for: stateKey) ?? stateKey.uppercased()
            return ("\(state) \(district)District Court", state, .district)
        }
        
        return (code.uppercased(), "Unknown", .district)
    }
    
    private func timezoneForState(_ state: String) -> String {
        let timezones: [String: String] = [
            "Alaska": "America/Anchorage",
            "Hawaii": "Pacific/Honolulu",
            "Guam": "Pacific/Guam", "Northern Mariana Islands": "Pacific/Saipan",
            "Puerto Rico": "America/Puerto_Rico", "Virgin Islands": "America/St_Thomas",
            "California": "America/Los_Angeles", "Nevada": "America/Los_Angeles",
            "Oregon": "America/Los_Angeles", "Washington": "America/Los_Angeles",
            "Arizona": "America/Phoenix",
            "Colorado": "America/Denver", "Montana": "America/Denver",
            "New Mexico": "America/Denver", "Utah": "America/Denver", "Wyoming": "America/Denver",
            "Alabama": "America/Chicago", "Arkansas": "America/Chicago", "Illinois": "America/Chicago",
            "Iowa": "America/Chicago", "Kansas": "America/Chicago", "Louisiana": "America/Chicago",
            "Minnesota": "America/Chicago", "Mississippi": "America/Chicago", "Missouri": "America/Chicago",
            "Nebraska": "America/Chicago", "North Dakota": "America/Chicago", "Oklahoma": "America/Chicago",
            "South Dakota": "America/Chicago", "Texas": "America/Chicago", "Wisconsin": "America/Chicago"
        ]
        return timezones[state] ?? "America/New_York"
    }
}
