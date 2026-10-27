import Foundation

actor RateLimiter {
    static let shared = RateLimiter()
    
    private var buckets: [String: [Date]] = [:]

    init() {}
    
    func allow(for key: String, maxRequests: Int, per interval: TimeInterval) -> Bool {
        let now = Date()
        var timestamps = buckets[key] ?? []
        timestamps = timestamps.filter { now.timeIntervalSince($0) < interval }
        
        guard timestamps.count < maxRequests else {
            buckets[key] = timestamps
            return false
        }
        
        timestamps.append(now)
        buckets[key] = timestamps

        if buckets.count > 64 {
            buckets = buckets.filter { _, dates in
                dates.contains { now.timeIntervalSince($0) < interval }
            }
        }

        return true
    }
}
