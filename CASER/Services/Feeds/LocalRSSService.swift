import Foundation
import CryptoKit
import os.log

private let rssLogger = Logger(subsystem: "com.caser.app", category: "LocalRSSService")

struct RSSItem: Codable, Equatable, Sendable {
    let title: String
    let link: String
    let description: String
    let pubDate: Date?
    let guid: String
}

struct FeedFetchResult: Sendable {
    let entries: [CaseEntry]
    let requestedFeedIDs: Set<String>
    let successfulFeedIDs: Set<String>
    let failedFeedIDs: Set<String>
    let wasCancelled: Bool

    var completedRequestedWindow: Bool {
        !wasCancelled && successfulFeedIDs.count + failedFeedIDs.count == requestedFeedIDs.count
    }
}

class RSSParser: NSObject, XMLParserDelegate {
    private static let maxParsedItems = 5_000
    private var rootElement: String?
    private var exceededItemLimit = false

    private var items: [RSSItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentGuid = ""
    private var isInItem = false
    private var hasPublishedDate = false
    private var sourceURL: URL?

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }
    }()

    func parse(data: Data, sourceURL: URL? = nil) throws -> [RSSItem] {
        items = []
        rootElement = nil
        exceededItemLimit = false
        currentElement = ""
        isInItem = false
        self.sourceURL = sourceURL
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        if #available(iOS 26.0, *) {
            parser.externalEntityResolvingPolicy = .never
        }
        parser.delegate = self
        let didParse = parser.parse()
        guard didParse, !exceededItemLimit,
              rootElement == "rss" || rootElement == "feed" || rootElement == "rdf" else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let elementName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if rootElement == nil { rootElement = elementName.lowercased() }
        currentElement = elementName
        if elementName == "item" || elementName == "entry" {
            isInItem = true
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentPubDate = ""
            currentGuid = ""
            hasPublishedDate = false
        }
        if isInItem, elementName == "published" || elementName == "pubDate" {
            hasPublishedDate = true
            currentPubDate = ""
        }
        if isInItem, elementName == "link", let href = attributeDict["href"],
           attributeDict["rel"] == nil || attributeDict["rel"] == "alternate" {
            currentLink = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "link": currentLink += string
        case "description", "summary", "content": currentDescription += string
        case "pubDate", "published": currentPubDate += string
        case "updated": if !hasPublishedDate { currentPubDate += string }
        case "guid", "id": currentGuid += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            self.parser(parser, foundCharacters: text)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let elementName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if elementName == "item" || elementName == "entry" {
            let pubDate = parseDate(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
            let guid = currentGuid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard items.count < Self.maxParsedItems else {
                isInItem = false
                exceededItemLimit = true
                parser.abortParsing()
                return
            }
            let item = RSSItem(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                link: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                description: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate: pubDate,
                guid: guid.isEmpty
                    ? Self.stableFallbackGUID(
                        sourceURL: sourceURL,
                        title: currentTitle,
                        link: currentLink,
                        description: currentDescription,
                        publicationText: currentPubDate
                    )
                    : guid
            )
            items.append(item)
            isInItem = false
        }
        currentElement = ""
    }

    private func parseDate(_ string: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: string) {
            return date
        }
        for formatter in Self.dateFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    static func stableFallbackGUID(
        sourceURL: URL?,
        title: String,
        link: String,
        description: String,
        publicationText: String
    ) -> String {
        let components = [
            sourceURL?.absoluteString ?? "",
            link.trimmingCharacters(in: .whitespacesAndNewlines),
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            publicationText.trimmingCharacters(in: .whitespacesAndNewlines),
            description.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        let digest = SHA256.hash(data: Data(components.joined(separator: "\u{1F}").utf8))
        return "fallback-" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

final class RSSRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url?.scheme?.lowercased() == "https",
              let host = request.url?.host?.lowercased() else {
            completionHandler(nil)
            return
        }
        if host.hasSuffix(".uscourts.gov") || host == "uscourts.gov"
            || host.hasSuffix(".govinfo.gov") || host == "govinfo.gov" {
            completionHandler(request)
        } else {
            os_log("Security: blocked RSS redirect to %{public}@", log: .default, type: .error, host)
            completionHandler(nil)
        }
    }
}

@MainActor
class LocalRSSService {
    static let shared = LocalRSSService()

    private let session: URLSession
    private let feedCache: FeedResponseCache
    private let redirectGuard = RSSRedirectGuard()

    init(session: URLSession? = nil, feedCache: FeedResponseCache = .shared) {
        self.feedCache = feedCache
        if let session {
            self.session = session
            return
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        self.session = URLSession(
            configuration: config,
            delegate: redirectGuard,
            delegateQueue: nil
        )
    }

    nonisolated static let maxRSSPayloadSize = 5 * 1024 * 1024

    nonisolated private static func isTrustedFeedHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "uscourts.gov" || lower.hasSuffix(".uscourts.gov")
            || lower == "govinfo.gov" || lower.hasSuffix(".govinfo.gov")
    }

    nonisolated func fetchFeed(from url: URL, timeout: TimeInterval = 10) async throws -> [RSSItem] {
        guard url.scheme?.lowercased() == "https" else {
            os_log("Security: Blocked HTTP request to %{public}@", log: .default, type: .error, url.absoluteString)
            throw URLError(.unsupportedURL, userInfo: [NSLocalizedDescriptionKey: "HTTP URLs are not supported for security reasons"])
        }

        guard let host = url.host, Self.isTrustedFeedHost(host) else {
            os_log("Security: Blocked RSS request to untrusted host %{public}@", log: .default, type: .error, url.absoluteString)
            throw URLError(.unsupportedURL, userInfo: [NSLocalizedDescriptionKey: "Feed host is not on the trusted allowlist"])
        }

        let cached = await feedCache.snapshot(for: url)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(cached?.etag, forHTTPHeaderField: "If-None-Match")
        request.setValue(cached?.lastModified, forHTTPHeaderField: "If-Modified-Since")
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 304, let cached {
            return cached.items
        }
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard data.count <= Self.maxRSSPayloadSize else {
            rssLogger.error("RSS payload too large: \(data.count) bytes from \(url.absoluteString)")
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Feed response exceeds maximum allowed size"])
        }

        let parser = RSSParser()
        let items = try parser.parse(data: data, sourceURL: url)
        await feedCache.store(
            items: items,
            etag: httpResponse.value(forHTTPHeaderField: "ETag"),
            lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified"),
            for: url
        )
        return items
    }

    func fetchFeedsWithResult(
        from courts: [CourtFeed],
        maxConcurrent: Int = 25,
        feedLimit: Int? = nil,
        timeBudget: TimeInterval? = nil,
        isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled },
        onProgress: (@Sendable (Int, Int, Int, Int) -> Void)? = nil,
        onEntriesReceived: (@Sendable ([CaseEntry]) -> Void)? = nil
    ) async -> FeedFetchResult {
        guard !courts.isEmpty else {
            return FeedFetchResult(
                entries: [], requestedFeedIDs: [], successfulFeedIDs: [],
                failedFeedIDs: [], wasCancelled: false
            )
        }
        let workingCourts: [CourtFeed] = {
            if let limit = feedLimit, limit > 0, limit < courts.count {
                return Array(courts.prefix(limit))
            }
            return courts
        }()
        let batchSize = max(1, maxConcurrent)
        var allEntries: [CaseEntry] = []
        var scannedCount = 0
        var failedCount = 0
        var successfulFeedIDs = Set<String>()
        var failedFeedIDs = Set<String>()
        var wasCancelled = false
        var index = 0
        let clock = ContinuousClock()
        let deadline = timeBudget.map { clock.now + .seconds($0) }
        var budgetExpired = false
        typealias Fetch = (courtID: String?, entries: [CaseEntry], failed: Bool, cancelled: Bool)

        await withTaskGroup(of: Fetch.self) { group in
            func enqueue(_ court: CourtFeed) {
                group.addTask { [court] in
                    guard !isCancelled() else { return (court.id, [], false, true) }
                    do {
                        let items = try await self.fetchFeed(from: court.url, timeout: timeBudget == nil ? 10 : 5)
                        guard !isCancelled() else { return (court.id, [], false, true) }
                        return (court.id, items.map { self.mapToCaseEntry($0, court: court) }, false, false)
                    } catch {
                        guard !isCancelled() else { return (court.id, [], false, true) }
                        rssLogger.error("Failed to fetch feed for court \(court.id): \(error)")
                        return (court.id, [], true, false)
                    }
                }
            }

            if let deadline {
                group.addTask {
                    try? await clock.sleep(until: deadline)
                    return (nil, [], false, true)
                }
            }
            for _ in 0..<min(batchSize, workingCourts.count) {
                enqueue(workingCourts[index])
                index += 1
            }

            while let result = await group.next() {
                if result.courtID == nil {
                    budgetExpired = true
                    group.cancelAll()
                    break
                }
                guard !isCancelled(), !result.cancelled else {
                    wasCancelled = true
                    group.cancelAll()
                    break
                }
                guard let courtID = result.courtID else { continue }
                if result.failed {
                    failedCount += 1
                    failedFeedIDs.insert(courtID)
                } else {
                    successfulFeedIDs.insert(courtID)
                }
                allEntries.append(contentsOf: result.entries)
                scannedCount += 1
                onProgress?(scannedCount, workingCourts.count, allEntries.count, failedCount)
                if !result.entries.isEmpty { onEntriesReceived?(result.entries) }
                if scannedCount == workingCourts.count {
                    group.cancelAll()
                    break
                }
                if index < workingCourts.count, deadline.map({ clock.now < $0 }) ?? true {
                    enqueue(workingCourts[index])
                    index += 1
                } else if index < workingCourts.count {
                    budgetExpired = true
                    group.cancelAll()
                    break
                }
            }
        }
        wasCancelled = wasCancelled || (isCancelled() && !budgetExpired)
        await feedCache.flush()

        return FeedFetchResult(
            entries: allEntries.sorted { ($0.pubDate ?? Date.distantPast) > ($1.pubDate ?? Date.distantPast) },
            requestedFeedIDs: Set(workingCourts.map(\.id)),
            successfulFeedIDs: successfulFeedIDs,
            failedFeedIDs: failedFeedIDs,
            wasCancelled: wasCancelled
        )
    }

    nonisolated func mapToCaseEntry(_ item: RSSItem, court: CourtFeed) -> CaseEntry {
        let validatedLink = URLValidator.safeCourtURL(item.link)?.absoluteString ?? ""
        return CaseEntry(
            objectID: item.guid,
            title: item.title,
            description: item.description,
            courtId: court.id,
            courtName: court.name,
            courtSlug: nil,
            caseType: nil,
            timezone: court.timezone,
            parties: [],
            link: validatedLink,
            guid: item.guid,
            documentLink: nil,
            pubDate: item.pubDate,
            createdAt: item.pubDate,
            state: court.state,
            feedId: court.id,
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
            modsCourtType: court.type.rawValue,
            modsCourtState: court.state,
            premisObjectId: nil,
            zipPrimaryPdfPath: nil,
            category: [],
            creator: nil,
            source: court.source.rawValue
        )
    }
}
