import Foundation

struct CaseMatch: Identifiable, Codable, Sendable {
    let id: String
    let keyword: String
    let keywordId: String?
    let caseId: String
    let courtId: String
    let title: String
    let matchedText: String
    let link: String
    var notified: Bool
    var read: Bool
    var starred: Bool
    let createdAt: Date
    
    let courtName: String?
    let caseNumber: String?
    let citation: String?
    let documentUrl: String?
    let pubDate: Date?
}

extension CaseMatch: CaseDisplayable {
    var description: String { matchedText }
    var matchedKeyword: String? { keyword }
    var displayCaseNumber: String? { caseNumber }
    var displayCitation: String? {
        guard let rawCitation = citation?.trimmedNonEmpty else { return nil }
        return rawCitation.sanitizedCitationText()
    }
    var docketURL: String? { link.trimmedNonEmpty }
    
    var primaryDocumentURL: String? {
        if let docUrl = documentUrl?.trimmedNonEmpty {
            return docUrl
        }
        if let embedded = matchedText.firstHref(matchingSuffixes: ["pdf", "zip", "doc", "docx"]) {
            return embedded
        }
        return link.trimmedNonEmpty
    }

    func asCaseEntry() -> CaseEntry {
        CaseEntry(
            objectID: caseId,
            title: title,
            description: matchedText,
            courtId: courtId,
            courtName: courtName,
            courtSlug: nil,
            caseType: nil,
            timezone: nil,
            parties: [],
            link: link,
            guid: nil,
            documentLink: documentUrl,
            pubDate: pubDate,
            createdAt: createdAt,
            state: nil,
            feedId: nil,
            govinfoCitation: citation,
            modsCaseNumber: caseNumber
        )
    }
}
