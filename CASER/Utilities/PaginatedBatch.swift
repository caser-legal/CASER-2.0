import Foundation

enum PaginatedBatch {
    static let pageSize = 100

    static func page<T>(_ items: [T], visibleCount: Int) -> [T] {
        Array(items.prefix(visibleCount))
    }

    static func canLoadMore(totalCount: Int, visibleCount: Int) -> Bool {
        visibleCount < totalCount
    }

    static func nextVisibleCount(current: Int, totalCount: Int) -> Int {
        min(current + pageSize, totalCount)
    }
}