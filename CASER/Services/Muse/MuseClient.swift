import Foundation
import os.log

private let museLogger = Logger(subsystem: "com.caser.app", category: "Muse")

struct MuseCitation: Codable, Hashable, Sendable {
    let title: String
    let url: String
}

struct CaseInsights: Codable, Equatable, Sendable {
    struct KeyTerm: Codable, Hashable, Sendable {
        let term: String
        let meaning: String
    }

    let summary: String
    let filingExplained: String
    let keyTerms: [KeyTerm]
    let whatToWatch: [String]
}

struct CaseAbout: Codable, Equatable, Sendable {
    struct Person: Codable, Hashable, Sendable {
        let name: String
        let role: String
    }

    struct TimelineEvent: Codable, Hashable, Sendable {
        let date: String
        let event: String
    }

    struct NewsItem: Codable, Hashable, Sendable {
        let outlet: String
        let summary: String
    }

    /// A run of prose followed by the sources (indexes into the research citations) that back it.
    struct CitedText: Codable, Hashable, Sendable {
        let text: String
        let sources: [Int]
    }

    var story: String
    var storySegments: [CitedText]
    var whosWho: [Person]
    var whereItStands: String
    var whereItStandsSegments: [CitedText]
    var timeline: [TimelineEvent]
    var inTheNews: [NewsItem]

    enum CodingKeys: String, CodingKey {
        case story
        case storySegments
        case whosWho
        case whereItStands
        case whereItStandsSegments
        case timeline
        case inTheNews
    }

    init(story: String, whosWho: [Person] = [], whereItStands: String = "", timeline: [TimelineEvent] = [], inTheNews: [NewsItem] = []) {
        self.story = story
        self.storySegments = []
        self.whosWho = whosWho
        self.whereItStands = whereItStands
        self.whereItStandsSegments = []
        self.timeline = timeline
        self.inTheNews = inTheNews
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let strip = Self.stripCitationMarkers
        storySegments = try container.decodeIfPresent([CitedText].self, forKey: .storySegments) ?? []
        whereItStandsSegments = try container.decodeIfPresent([CitedText].self, forKey: .whereItStandsSegments) ?? []
        story = strip(try container.decodeIfPresent(String.self, forKey: .story) ?? "")
        whosWho = (try container.decodeIfPresent([Person].self, forKey: .whosWho) ?? [])
            .map { Person(name: $0.name, role: strip($0.role)) }
        whereItStands = strip(try container.decodeIfPresent(String.self, forKey: .whereItStands) ?? "")
        timeline = (try container.decodeIfPresent([TimelineEvent].self, forKey: .timeline) ?? [])
            .map { TimelineEvent(date: $0.date, event: strip($0.event)) }
        inTheNews = (try container.decodeIfPresent([NewsItem].self, forKey: .inTheNews) ?? [])
            .map { NewsItem(outlet: $0.outlet, summary: strip($0.summary)) }
    }

    /// Sources come from Meta's url_citation annotations, so [1]-style markers the model
    /// typed itself (still present in older cached results) are dropped rather than shown.
    static func stripCitationMarkers(_ text: String) -> String {
        guard text.contains("[") else { return text }
        return text.replacingOccurrences(
            of: #"\s*\[\d{1,2}(?:\s*[,–-]\s*\d{1,2})*\]"#,
            with: "",
            options: .regularExpression
        )
    }

    /// True when the story is readable prose rather than leftover model JSON.
    var hasReadableStory: Bool {
        let trimmed = story.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("{") && !trimmed.hasPrefix("```") && !trimmed.contains("\"story\"")
    }

    static func parseLegacyBrief(_ text: String) -> CaseAbout {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("```") {
            let unfenced = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let start = unfenced.firstIndex(of: "{"),
               let end = unfenced.lastIndex(of: "}"),
               let data = String(unfenced[start...end]).data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                func text(_ key: String) -> String { (object[key] as? String) ?? "" }
                func pairs(_ key: String, _ first: String, _ second: String) -> [[String: String]] {
                    (object[key] as? [[String: Any]] ?? []).map {
                        [first: ($0[first] as? String) ?? "", second: ($0[second] as? String) ?? ""]
                    }
                }
                return CaseAbout(
                    story: text("story"),
                    whosWho: pairs("whos_who", "name", "role").map { Person(name: $0["name"] ?? "", role: $0["role"] ?? "") },
                    whereItStands: text("where_it_stands"),
                    timeline: pairs("timeline", "date", "event").map { TimelineEvent(date: $0["date"] ?? "", event: $0["event"] ?? "") },
                    inTheNews: pairs("in_the_news", "outlet", "summary").map { NewsItem(outlet: $0["outlet"] ?? "", summary: $0["summary"] ?? "") }
                )
            }
            // Unreadable JSON is never shown as the story.
            return CaseAbout(story: "")
        }
        var about = CaseAbout(story: "")
        var section = "story"
        var storyLines: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let heading = line.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces).lowercased()
            switch heading {
            case "the story": section = "story"; continue
            case "who's who": section = "whos"; continue
            case "where it stands": section = "stands"; continue
            case "timeline": section = "timeline"; continue
            case "in the news": section = "news"; continue
            default: break
            }
            guard !line.isEmpty else { continue }
            switch section {
            case "story":
                storyLines.append(line)
            case "whos":
                let parts = line.components(separatedBy: " — ")
                if parts.count > 1 { about.whosWho.append(Person(name: parts[0], role: parts.dropFirst().joined(separator: " — "))) }
            case "stands":
                about.whereItStands = [about.whereItStands, line].filter { !$0.isEmpty }.joined(separator: " ")
            case "timeline":
                let parts = line.components(separatedBy: " — ")
                if parts.count > 1 { about.timeline.append(TimelineEvent(date: parts[0], event: parts.dropFirst().joined(separator: " — "))) }
            case "news":
                let parts = line.components(separatedBy: " — ")
                if parts.count > 1 { about.inTheNews.append(NewsItem(outlet: parts[0], summary: parts.dropFirst().joined(separator: " — "))) }
            default:
                break
            }
        }
        about.story = storyLines.joined(separator: " ")
        if about.story.isEmpty { about.story = text }
        return about
    }
}

struct CaseResearch: Codable, Equatable, Sendable {
    let brief: String
    let citations: [MuseCitation]
    var about: CaseAbout
    var thinking: String

    enum CodingKeys: String, CodingKey {
        case brief
        case citations
        case about
        case thinking
    }

    init(brief: String, citations: [MuseCitation], about: CaseAbout? = nil, thinking: String = "") {
        self.brief = brief
        self.citations = citations
        self.about = about ?? CaseAbout.parseLegacyBrief(brief)
        self.thinking = thinking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brief = try container.decodeIfPresent(String.self, forKey: .brief) ?? ""
        citations = try container.decodeIfPresent([MuseCitation].self, forKey: .citations) ?? []
        thinking = try container.decodeIfPresent(String.self, forKey: .thinking) ?? ""
        if let decoded = try container.decodeIfPresent(CaseAbout.self, forKey: .about) {
            about = decoded
            if about.story.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                let reparsed = CaseAbout.parseLegacyBrief(about.story)
                if !reparsed.story.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                    about = reparsed
                }
            }
        } else {
            about = CaseAbout.parseLegacyBrief(brief)
        }
    }
}

struct CaseAnswer: Codable, Equatable, Sendable {
    let text: String
    let citations: [MuseCitation]
    var thinking: String
    var toolUsed: String

    enum CodingKeys: String, CodingKey {
        case text
        case citations
        case thinking
        case toolUsed
    }

    init(text: String, citations: [MuseCitation], thinking: String = "", toolUsed: String = "") {
        self.text = text
        self.citations = citations
        self.thinking = thinking
        self.toolUsed = toolUsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        citations = try container.decodeIfPresent([MuseCitation].self, forKey: .citations) ?? []
        thinking = try container.decodeIfPresent(String.self, forKey: .thinking) ?? ""
        toolUsed = try container.decodeIfPresent(String.self, forKey: .toolUsed) ?? ""
    }
}

struct MuseStreamEvent: Sendable {
    enum Kind: Sendable {
        case text(String)
        case thinking(String)
        case tool(String)
        case sources([MuseCitation])
        case done
    }

    let kind: Kind
}

struct MuseCaseContext: Encodable, Equatable, Sendable {
    let title: String
    let docketText: String
    let court: String
    let caseNumber: String
    let filedDate: String
    let caseType: String
    let state: String
    let citation: String
    let parties: [String]
    let link: String

    init(entry: CaseEntry) {
        title = String(entry.displayTitle.prefix(500))
        let summary = entry.cleanedSummary
        docketText = summary == CaseEntry.summaryPlaceholder ? "" : String(summary.prefix(6000))
        court = String(resolveCourtName(courtId: entry.courtId, explicitName: entry.courtName).prefix(200))
        caseNumber = String((entry.displayCaseNumber ?? "").prefix(120))
        filedDate = entry.pubDate.map { $0.formatted(.iso8601.year().month().day()) } ?? ""
        caseType = String((entry.modsCourtType?.trimmedNonEmpty ?? entry.caseType?.trimmedNonEmpty ?? "").prefix(120))
        state = String((entry.modsCourtState?.trimmedNonEmpty ?? entry.state?.trimmedNonEmpty ?? "").prefix(80))
        citation = String((entry.displayCitation ?? "").prefix(300))
        parties = entry.parties
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(60)
            .map { String($0.prefix(300)) }
        if let raw = entry.link.trimmedNonEmpty,
           let url = URLValidator.safeURL(raw),
           url.scheme?.lowercased() == "https" {
            link = String(url.absoluteString.prefix(2048))
        } else {
            link = ""
        }
    }
}

struct MuseFollowUpTurn: Encodable, Equatable, Sendable {
    let question: String
    let answer: String
}

struct MuseCaseNotes: Encodable, Equatable, Sendable {
    let summary: String
    let research: String
}

enum MuseError: LocalizedError, Equatable {
    case notConfigured
    case offline
    case busy
    case timedOut
    case rejected
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Atticus isn't connected yet. Please try again later."
        case .offline:
            return "You're offline. Connect to the internet and try again."
        case .busy:
            return "Atticus is busy right now. Please try again in a moment."
        case .timedOut:
            return "Atticus took too long to respond. Please try again."
        case .rejected:
            return "Atticus couldn't read this case. Please try again."
        case .unavailable:
            return "Atticus is unavailable right now. Please try again."
        }
    }

    static func message(for error: Error) -> String {
        (error as? MuseError ?? .unavailable).errorDescription ?? MuseError.unavailable.errorDescription!
    }
}

actor MuseClient {
    static let shared = MuseClient()

    private struct CaseRequest: Encodable {
        let entry: MuseCaseContext
    }

    private struct QuestionRequest: Encodable {
        let entry: MuseCaseContext
        let notes: MuseCaseNotes
        let history: [MuseFollowUpTurn]
        let question: String
    }

    private struct InsightsEnvelope: Decodable {
        let insights: CaseInsights
    }

    private struct ResearchEnvelope: Decodable {
        let research: CaseResearch
    }

    private struct AnswerEnvelope: Decodable {
        let answer: CaseAnswer
    }

    private struct StreamChunk: Decodable {
        let type: String
        let delta: String?
        let name: String?
        let citations: [MuseCitation]?
        let code: String?
    }

    private struct ErrorEnvelope: Decodable {
        let error: String
    }

    private static let maximumResponseBytes = 256 * 1024

    private let session: URLSession
    private let baseURL: URL?
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        baseURL = Self.configuredBaseURL()
    }

    func insights(for context: MuseCaseContext) async throws -> CaseInsights {
        let envelope: InsightsEnvelope = try await post(
            "v1/case-insights",
            body: CaseRequest(entry: context)
        )
        return envelope.insights
    }

    func research(for context: MuseCaseContext) async throws -> CaseResearch {
        let envelope: ResearchEnvelope = try await post(
            "v1/case-research",
            body: CaseRequest(entry: context)
        )
        return envelope.research
    }

    func ask(
        _ question: String,
        about context: MuseCaseContext,
        notes: MuseCaseNotes,
        history: [MuseFollowUpTurn]
    ) async throws -> CaseAnswer {
        let envelope: AnswerEnvelope = try await post(
            "v1/case-question",
            body: QuestionRequest(
                entry: context,
                notes: notes,
                history: Array(history.suffix(6)),
                question: question
            )
        )
        return envelope.answer
    }

    func askStreaming(
        _ question: String,
        about context: MuseCaseContext,
        notes: MuseCaseNotes,
        history: [MuseFollowUpTurn]
    ) -> AsyncThrowingStream<MuseStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let baseURL else { throw MuseError.notConfigured }
                    var request = URLRequest(url: baseURL.appending(path: "v1/case-question-stream"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(
                        QuestionRequest(entry: context, notes: notes, history: Array(history.suffix(6)), question: question)
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw MuseError.unavailable
                    }
                    var sawText = false
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? decoder.decode(StreamChunk.self, from: data) else { continue }
                        switch chunk.type {
                        case "text":
                            if let delta = chunk.delta, !delta.isEmpty {
                                sawText = true
                                continuation.yield(MuseStreamEvent(kind: .text(delta)))
                            }
                        case "thinking":
                            if let delta = chunk.delta, !delta.isEmpty {
                                continuation.yield(MuseStreamEvent(kind: .thinking(delta)))
                            }
                        case "tool":
                            continuation.yield(MuseStreamEvent(kind: .tool(chunk.name ?? "")))
                        case "sources":
                            continuation.yield(MuseStreamEvent(kind: .sources(chunk.citations ?? [])))
                        case "done":
                            continuation.yield(MuseStreamEvent(kind: .done))
                        case "error":
                            throw MuseError.unavailable
                        default:
                            continue
                        }
                    }
                    guard sawText else { throw MuseError.unavailable }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as MuseError {
                    continuation.finish(throwing: error)
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: MuseError.unavailable)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func post<Response: Decodable>(_ path: String, body: some Encodable) async throws -> Response {
        guard let baseURL else { throw MuseError.notConfigured }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw CancellationError()
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                throw MuseError.offline
            case .timedOut:
                throw MuseError.timedOut
            default:
                museLogger.error("Muse request failed: \(error.code.rawValue, privacy: .public)")
                throw MuseError.unavailable
            }
        }

        guard let http = response as? HTTPURLResponse else { throw MuseError.unavailable }
        guard data.count <= Self.maximumResponseBytes else { throw MuseError.unavailable }

        guard (200..<300).contains(http.statusCode) else {
            let code = (try? decoder.decode(ErrorEnvelope.self, from: data))?.error ?? ""
            museLogger.error("Muse backend returned \(http.statusCode, privacy: .public) \(code, privacy: .public)")
            switch http.statusCode {
            case 429:
                throw MuseError.busy
            case 503 where code == "ai_not_configured":
                throw MuseError.notConfigured
            case 504:
                throw MuseError.timedOut
            case 400, 413, 415:
                throw MuseError.rejected
            default:
                throw MuseError.unavailable
            }
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            museLogger.error("Muse response could not be decoded")
            throw MuseError.unavailable
        }
    }

    private static func configuredBaseURL() -> URL? {
        guard let raw = (Bundle.main.object(forInfoDictionaryKey: "MuseBackendURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              !raw.hasPrefix("$("),
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }
}
