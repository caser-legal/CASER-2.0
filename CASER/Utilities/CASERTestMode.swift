import Foundation

enum CASERTestMode {
    #if DEBUG
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--caser-ui-testing")
    }
    #else
    static let isUITesting = false
    #endif
}
