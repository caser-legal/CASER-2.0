import Foundation
import os.log

private let archiveLogger = Logger(subsystem: "com.caser.app", category: "FeedArchive")

actor FeedArchiveClient {
    static let shared = FeedArchiveClient()

    private struct ArchiveResponse: Decodable {
        struct Match: Decodable {
            let id: String
            let title: String
            let description: String
            let court: String
            let state: String
            let courtType: String
            let publishedAt: String?
            let link: String?

            enum CodingKeys: String, CodingKey {
                case id
                case title
                case description
                case court
                case state
                case courtType = "court_type"
                case publishedAt = "published_at"
                case link
            }
        }

        let matches: [Match]
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    static var baseURL: URL? {
        guard let raw = (Bundle.main.object(forInfoDictionaryKey: "MuseBackendURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              !raw.hasPrefix("$("),
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }

    static var endpoint: URL? {
        baseURL?.appending(path: "v1/docket-archive")
    }

    func search(query: String, days: Int = 30) async -> [CaseEntry] {
        guard let baseURL = Self.baseURL,
              let endpoint = Self.endpoint,
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "query", value: String(query.prefix(200))),
            URLQueryItem(name: "days", value: String(min(max(days, 1), 30))),
        ]
        guard let url = components.url else { return [] }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            var data = Data()
            var response: URLResponse?
            for attempt in 0..<2 {
                request.setValue(try await MuseClient.deviceToken(baseURL: baseURL), forHTTPHeaderField: DeviceAttestor.header)
                (data, response) = try await session.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 401, attempt == 0 {
                    await DeviceAttestor.shared.reset()
                    continue
                }
                break
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                archiveLogger.debug("Archive search returned a non-200 status")
                return []
            }
            let decoded = try JSONDecoder().decode(ArchiveResponse.self, from: data)
            return decoded.matches.map(Self.mapToCaseEntry)
        } catch is CancellationError {
            return []
        } catch {
            archiveLogger.debug("Archive search failed: \(error.localizedDescription)")
            return []
        }
    }

    private static func mapToCaseEntry(_ match: ArchiveResponse.Match) -> CaseEntry {
        let parts = match.id.split(separator: "|", maxSplits: 1).map(String.init)
        let feedID = parts.count == 2 ? parts[0] : match.court
        let guid = parts.count == 2 ? parts[1] : match.id
        let published = match.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        let link = match.link.flatMap { URLValidator.safeCourtURL($0)?.absoluteString } ?? ""
        return CaseEntry(
            objectID: guid,
            title: match.title,
            description: match.description,
            courtId: feedID,
            courtName: match.court,
            courtSlug: nil,
            caseType: nil,
            timezone: nil,
            parties: [],
            link: link,
            guid: guid,
            documentLink: nil,
            pubDate: published,
            createdAt: published,
            state: match.state,
            feedId: feedID,
            govinfoZipUrl: nil,
            govinfoPdfUrl: nil,
            govinfoModsUrl: nil,
            govinfoPremisUrl: nil,
            govinfoHtmlUrl: nil,
            govinfoSummaryXmlUrl: nil,
            govinfoSummary: nil,
            govinfoContextHtml: nil,
            govinfoCitation: nil,
            modsTitle: nil,
            modsCaseNumber: nil,
            modsSubjects: [],
            modsPdfUrls: [],
            modsCourtType: match.courtType,
            modsCourtState: match.state,
            premisObjectId: nil,
            zipPrimaryPdfPath: nil,
            category: [],
            creator: nil,
            source: "archive"
        )
    }
}
