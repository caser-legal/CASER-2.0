import AppIntents
import Foundation

struct SearchAlertNowIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Search Courts Now"
    static let description: IntentDescription? = IntentDescription(
        "Checks the federal court feeds for this alert's keyword right now."
    )
    static let isDiscoverable = false

    @Parameter(title: "Alert ID")
    var keywordId: String

    init() {}

    init(keywordId: String) {
        self.keywordId = keywordId
    }

    func perform() async throws -> some IntentResult {
        #if !CASER_WIDGET_EXTENSION
        await CaserLiveActivity.searchNow(keywordId: keywordId)
        #endif
        return .result()
    }
}
