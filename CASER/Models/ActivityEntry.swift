import Foundation

enum ActivityType: String, Codable, Sendable {
    case search, monitor, system
}

struct SearchActivityMetadata: Codable, Sendable {
    let query: String
    let filters: [String]
    let resultCount: Int
    let hits: Int
    let pageSize: Int
    let pagesBilled: Int
}

struct MonitorActivityMetadata: Codable, Sendable {
    let keyword: String
    let caseId: String
    let courtId: String
    let billableResults: Int
    let billablePages: Int

    init(keyword: String, caseId: String, courtId: String, billableResults: Int = 1, billablePages: Int = 1) {
        self.keyword = keyword
        self.caseId = caseId
        self.courtId = courtId
        self.billableResults = billableResults
        self.billablePages = billablePages
    }
}

struct ActivityEntry: Codable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var type: ActivityType
    var title: String
    var description: String
    var timestamp: Date = Date()
    var searchMetadata: SearchActivityMetadata?
    var monitorMetadata: MonitorActivityMetadata?
}
