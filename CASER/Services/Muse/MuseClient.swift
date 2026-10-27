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

struct CaseResearch: Codable, Equatable, Sendable {
    let brief: String
    let citations: [MuseCitation]
}

struct CaseAnswer: Codable, Equatable, Sendable {
    let text: String
    let citations: [MuseCitation]
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
