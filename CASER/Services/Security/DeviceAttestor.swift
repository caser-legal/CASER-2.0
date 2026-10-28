import CryptoKit
import DeviceCheck
import Foundation
import os.log

private let attestLogger = Logger(subsystem: "com.caser.app", category: "DeviceAttest")

actor DeviceAttestor {
    static let shared = DeviceAttestor()
    static let header = "X-CASER-Device"
    static let assertionHeader = "X-CASER-Assertion"
    static let assertionTimeHeader = "X-CASER-Assertion-Time"

    enum AttestorError: Error {
        case unsupported
        case unavailable
    }

    private struct ChallengeResponse: Decodable {
        let challenge: String
    }

    private struct AttestRequest: Encodable {
        let keyId: String
        let attestation: String
        let challenge: String

        enum CodingKeys: String, CodingKey {
            case keyId = "key_id"
            case attestation
            case challenge
        }
    }

    private struct TokenResponse: Decodable {
        let token: String
        let expiresAt: String

        enum CodingKeys: String, CodingKey {
            case token
            case expiresAt = "expires_at"
        }
    }

    private struct StoredPass: Codable {
        let token: String
        let expiresAt: Date
        let keyId: String?
    }

    private static let passKey = "caser.device-pass"
    private static let renewalMargin: TimeInterval = 60 * 60

    private let session: URLSession
    private var pending: Task<String, Error>?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func token(baseURL: URL) async throws -> String {
        if let stored = Self.storedPass(), stored.expiresAt.timeIntervalSinceNow > Self.renewalMargin {
            return stored.token
        }
        if let pending {
            return try await pending.value
        }
        let task = Task { try await self.attest(baseURL: baseURL) }
        pending = task
        defer { pending = nil }
        return try await task.value
    }

    func reset() {
        try? KeychainHelper.delete(for: Self.passKey)
    }

    func sign(_ request: inout URLRequest) async {
        guard let keyId = Self.storedPass()?.keyId,
              let url = request.url,
              let method = request.httpMethod?.uppercased() else { return }
        let time = String(Int64(Date().timeIntervalSince1970 * 1000))
        let bodyHash = SHA256.hash(data: request.httpBody ?? Data()).map { String(format: "%02x", $0) }.joined()
        let clientData = Data("\(method)\n\(url.path)\n\(bodyHash)\n\(time)".utf8)
        do {
            let assertion = try await DCAppAttestService.shared.generateAssertion(
                keyId,
                clientDataHash: Data(SHA256.hash(data: clientData))
            )
            request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: Self.assertionHeader)
            request.setValue(time, forHTTPHeaderField: Self.assertionTimeHeader)
        } catch let error as DCError where error.code == .invalidKey {
            attestLogger.error("App Attest key is no longer valid; attesting again")
            reset()
        } catch {
            attestLogger.error("App Attest assertion failed")
        }
    }

    private func attest(baseURL: URL) async throws -> String {
        let service = DCAppAttestService.shared
        guard service.isSupported else { throw AttestorError.unsupported }

        let challenge = try await fetchChallenge(baseURL: baseURL)
        let keyId = try await service.generateKey()
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)

        var request = URLRequest(url: baseURL.appending(path: "v1/attest"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            AttestRequest(keyId: keyId, attestation: attestation.base64EncodedString(), challenge: challenge)
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            attestLogger.error("Device attestation was refused")
            throw AttestorError.unavailable
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let expiresAt = formatter.date(from: decoded.expiresAt) else { throw AttestorError.unavailable }
        if let stored = try? JSONEncoder().encode(StoredPass(token: decoded.token, expiresAt: expiresAt, keyId: keyId)) {
            try? KeychainHelper.save(data: stored, for: Self.passKey)
        }
        return decoded.token
    }

    private func fetchChallenge(baseURL: URL) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "v1/attest/challenge"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AttestorError.unavailable
        }
        return try JSONDecoder().decode(ChallengeResponse.self, from: data).challenge
    }

    private static func storedPass() -> StoredPass? {
        guard let data = try? KeychainHelper.load(for: passKey) else { return nil }
        return try? JSONDecoder().decode(StoredPass.self, from: data)
    }
}
