import CryptoKit
import Foundation
import UIKit
import os.log

private let consentLogger = Logger(subsystem: "com.caser.app", category: "AIDisclaimerConsent")

enum AIDisclaimer {
    static let version = "atticus-disclaimer-v3.1-2026-10-28"

    static let title = "Before You Use Atticus"

    static let intro = "Atticus is an AI tool, not a lawyer. It provides general legal information, not legal advice, and is not a substitute for the advice of an attorney."

    static let points = [
        "Using Atticus does not create an attorney-client relationship. Your questions are not confidential or privileged.",
        "AI answers can be wrong, incomplete, or out of date, and laws vary by state. Verify anything important with an attorney licensed in your state.",
        "Do not rely on Atticus for emergencies or court deadlines.",
        "To explain a case and answer your questions, the case details you open and the questions you ask are sent to Meta's Muse AI through CASER's server. Public court records may be used by Meta to improve its models; your typed questions are not. Do not enter confidential, privileged, or sensitive personal information.",
        "If Muse can't be reached, Atticus answers with Apple Intelligence on your iPhone or Apple Private Cloud Compute, or shows a summary taken from the docket."
    ]

    static let privacyPolicyURL = "https://www.caserlegal.com/privacy"
    static let termsURL = "https://www.caserlegal.com/terms"

    static let consentStatement = "By tapping Accept, you agree to these terms and to sharing the case details you open and your questions with Meta as described in our Privacy Policy and Terms of Use."

    static var fullText: String {
        ([title, intro] + points.map { "• \($0)" } + [consentStatement]).joined(separator: "\n")
    }

    static var textSHA256: String {
        SHA256.hash(data: Data(fullText.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct AIDisclaimerConsentRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let action: String
    let buttonLabel: String
    let disclaimerVersion: String
    let textSHA256: String
    let fullText: String
    let privacyPolicyURL: String
    let termsURL: String
    let thirdPartyAISharingConsent: Bool
    let acceptedAt: Date
    let timeZone: String
    let locale: String
    let installID: String
    let appVersion: String
    let osVersion: String
    let deviceModel: String
}

@MainActor
@Observable
final class AIDisclaimerConsent {
    static let shared = AIDisclaimerConsent()

    private(set) var acceptedVersion: String?

    var hasAcceptedCurrentVersion: Bool { acceptedVersion == AIDisclaimer.version }

    private let store = SecureFileStore()
    private static let logFile = "ai_disclaimer_consent_log.json"
    private static let acceptedVersionKey = "ai_disclaimer_accepted_version"
    private static let installIDKey = "caser_install_id"

    private init() {
        #if DEBUG
        if CASERTestMode.isUITesting {
            acceptedVersion = AIDisclaimer.version
            return
        }
        #endif
        acceptedVersion = (try? KeychainHelper.load(for: Self.acceptedVersionKey))
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    func accept() throws -> AIDisclaimerConsentRecord {
        let info = Bundle.main.infoDictionary
        let appVersion = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let record = AIDisclaimerConsentRecord(
            id: UUID(),
            action: "accept",
            buttonLabel: "Accept",
            disclaimerVersion: AIDisclaimer.version,
            textSHA256: AIDisclaimer.textSHA256,
            fullText: AIDisclaimer.fullText,
            privacyPolicyURL: AIDisclaimer.privacyPolicyURL,
            termsURL: AIDisclaimer.termsURL,
            thirdPartyAISharingConsent: true,
            acceptedAt: Date(),
            timeZone: TimeZone.current.identifier,
            locale: Locale.current.identifier,
            installID: try installID(),
            appVersion: appVersion,
            osVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            deviceModel: Self.deviceModel
        )

        var log = records()
        log.append(record)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try store.save(try encoder.encode(log), to: Self.logFile)

        try KeychainHelper.save(data: Data(AIDisclaimer.version.utf8), for: Self.acceptedVersionKey)
        acceptedVersion = AIDisclaimer.version
        consentLogger.info("AI disclaimer accepted, version \(AIDisclaimer.version, privacy: .public)")
        return record
    }

    func records() -> [AIDisclaimerConsentRecord] {
        guard let data = try? store.load(from: Self.logFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AIDisclaimerConsentRecord].self, from: data)) ?? []
    }

    func resetAcceptance() {
        try? KeychainHelper.delete(for: Self.acceptedVersionKey)
        acceptedVersion = nil
    }

    private func installID() throws -> String {
        if let data = try? KeychainHelper.load(for: Self.installIDKey),
           let id = String(data: data, encoding: .utf8) {
            return id
        }
        let id = UUID().uuidString
        try KeychainHelper.save(
            data: Data(id.utf8),
            for: Self.installIDKey,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
        return id
    }

    private static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
