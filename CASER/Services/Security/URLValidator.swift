import Foundation

enum URLValidator {
    private static let allowedSchemes: Set<String> = ["https", "mailto"]
    private static let systemSchemes: Set<String> = ["app-settings"]

    static let courtHostSuffixes: [String] = [
        "uscourts.gov",
        "govinfo.gov",
        "pacer.gov"
    ]

    static func isCourtDomain(_ host: String, additionalSuffixes: [String] = []) -> Bool {
        let normalized = host.lowercased()
        let suffixes = courtHostSuffixes + additionalSuffixes
        return suffixes.contains { suffix in
            normalized == suffix || normalized.hasSuffix(".\(suffix)")
        }
    }

    static func safeURL(_ string: String) -> URL? {
        guard let url = URL(string: string) else { return nil }
        return safeURL(url)
    }

    static func safeURL(_ string: String, allowedHosts: Set<String>?) -> URL? {
        guard let url = safeURL(string) else { return nil }
        return validateHost(url, allowedHosts: allowedHosts)
    }

    static func safeURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme) else {
            return nil
        }
        return url
    }

    static func safeURL(_ url: URL, allowedHosts: Set<String>?) -> URL? {
        guard let validated = safeURL(url) else { return nil }
        return validateHost(validated, allowedHosts: allowedHosts)
    }

    private static let groundingHostSuffixes: [String] = [
        "google.com",
        "wikipedia.org",
        "law.cornell.edu",
        "supremecourt.gov",
        "justice.gov"
    ]

    static func safeCourtURL(_ string: String) -> URL? {
        guard let url = safeURL(string),
              let host = url.host,
              isCourtDomain(host) else { return nil }
        return url
    }

    static func safeGroundingURL(_ string: String) -> URL? {
        if let courtURL = safeCourtURL(string) { return courtURL }
        guard let url = safeURL(string), let host = url.host?.lowercased() else { return nil }
        let trusted = groundingHostSuffixes.contains { suffix in
            host == suffix || host.hasSuffix(".\(suffix)")
        }
        guard trusted, !isOpenRedirect(url, host: host) else { return nil }
        return url
    }

    private static func isOpenRedirect(_ url: URL, host: String) -> Bool {
        guard host == "google.com" || host.hasSuffix(".google.com") else { return false }
        let path = url.path.lowercased()
        return path == "/url" || path == "/imgres" || path.hasPrefix("/amp/")
    }

    static func safeSystemURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              systemSchemes.contains(scheme) else {
            return nil
        }
        return url
    }

    static func isSafeMarkdownLink(_ url: URL) -> Bool {
        let string = url.absoluteString
        if url.scheme?.lowercased() == "mailto" {
            return safeURL(string) != nil
        }
        return safeGroundingURL(string) != nil
    }

    private static func validateHost(_ url: URL, allowedHosts: Set<String>?) -> URL? {
        guard let allowedHosts else { return url }
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else { return nil }
        return url
    }
}
