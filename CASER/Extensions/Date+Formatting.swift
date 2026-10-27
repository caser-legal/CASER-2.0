import Foundation
import SwiftUI

extension DateFormatter {
    static let filingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy h:mm a z"
        formatter.timeZone = .current
        return formatter
    }()
}

extension Date {
    func filingDisplayString() -> String {
        DateFormatter.filingDateFormatter.string(from: self)
    }
}

extension String {
    func formattedMarkdown() -> AttributedString {
        if let attributed = try? AttributedString(markdown: self) {
            return attributed
        }
        
        return AttributedString(self)
    }
    
    func cleanHTML() -> String {
        return self
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removingGovInfoMetadataBlock() -> String {
        guard !isEmpty else { return self }
        var text = self
        if let range = text.range(of: #"(?i)metadata\s+download"#, options: .regularExpression) {
            text = String(text[..<range.lowerBound])
        }
        if let range = text.range(of: #"(?i)descriptive\s+metadata"#, options: .regularExpression) {
            text = String(text[..<range.lowerBound])
        }
        if let range = text.range(of: #"(?i)all\s+content\s+and\s+metadata\s+files"#, options: .regularExpression) {
            text = String(text[..<range.lowerBound])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let metadataIndicators = ["descriptive metadata", "preservation metadata", "mods", "premis", "metadata download", "all content and metadata files"]
        let indicatorHits = metadataIndicators.filter { lower.contains($0) }.count
        if indicatorHits >= 2 || lower.hasPrefix("metadata download") {
            return ""
        }
        return text
    }


    func cleanedCitationText() -> String? {
        var working = self
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        working = working.replacingOccurrences(
            of: #"<a\b[^>]*>(.*?)</a>"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        working = working.cleanHTML()
        working = working.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "$1",
            options: [.regularExpression]
        )
        working = working.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        working = working.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !working.isEmpty else { return nil }

        if let metadataRange = working.range(
            of: #"(?i)^metadata\s+download(?:\s+options)?[:\s-]*"#,
            options: [.regularExpression]
        ) {
            working.removeSubrange(metadataRange)
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func extractSection(after keyword: String, in text: String) -> String? {
            guard let range = text.range(of: keyword, options: [.caseInsensitive]) else { return nil }
            var section = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if section.hasPrefix(":") {
                section.removeFirst()
                section = section.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let stopWords = ["SuDoc", "URL", "Metadata", "Download", "Source", "Related", "Access"]
            if let stopRange = stopWords
                .compactMap({ section.range(of: $0, options: [.caseInsensitive]) })
                .map({ $0.lowerBound })
                .sorted()
                .first {
                section = section[..<stopRange].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return section.isEmpty ? nil : String(section)
        }

        if let citationSection = extractSection(after: "Citation", in: working) {
            return citationSection
        }

        return working.isEmpty ? nil : working
    }

    func sanitizedCitationText() -> String? {
        func normalize(_ value: String) -> String {
            var text = value
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&apos;", with: "'")
            text = text.replacingOccurrences(
                of: #"\[([^\]]+)\]\(<a\b[^>]*>(.*?)</a>\)"#,
                with: "$1 $2",
                options: [.regularExpression, .caseInsensitive]
            )
            text = text.replacingOccurrences(
                of: #"\(<a\b[^>]*>(.*?)</a>\)"#,
                with: "$1",
                options: [.regularExpression, .caseInsensitive]
            )
            return text
                .replacingOccurrences(of: #"\[(.*?)\]"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"\((?:https?|www)[^)]+\)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let cleaned = cleanedCitationText(), !cleaned.isEmpty {
            let normalized = normalize(cleaned)
            if !normalized.isEmpty {
                return normalized
            }
        }
        let fallback = normalize(cleanHTML().removingGovInfoMetadataBlock())
        return fallback.isEmpty ? nil : fallback
    }

    func sanitizedSnippetText() -> String {
        var text = self
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")

        text = text.replacingOccurrences(
            of: #"\[(.*?)\]\(<a\b[^>]*>(.*?)</a>\)"#,
            with: "$1 $2",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"\(<a\b[^>]*>(.*?)</a>\)"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<a\b[^>]*>(.*?)</a>"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"\[(.*?)\]\((?:https?|www)[^)]+\)"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )

        text = text.cleanHTML()
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func removingLeadingCaseIdentifier() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        let patterns = [
            #"^(?:case\s+no\.?\s*|case\s+|no\.?\s+|#\s*)?(?:\d{1,2}:\d{2}-[a-z]{2,4}-\d{4,5}(?:-[a-z0-9]+)?)"#,
            #"^(?:case\s+no\.?\s*|case\s+|no\.?\s+|#\s*)?\d{2,4}-\d{3,5}"#
        ]
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—:|"))
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = regex.firstMatch(in: trimmed, options: [], range: range), match.range.location == 0,
               let matchRange = Range(match.range, in: trimmed) {
                let remainder = trimmed[matchRange.upperBound...]
                let cleaned = remainder.trimmingCharacters(in: separators)
                if !cleaned.isEmpty {
                    return cleaned
                }
                return trimmed
            }
        }
        return trimmed
    }

    func normalizedURLString() -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var normalized = trimmed
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized.lowercased()
    }

    func firstAnchorURL(where predicate: (String, String) -> Bool) -> String? {
        let pattern = #"<a\b[^>]*href=[\"']([^\"'>]+)[\"'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(location: 0, length: (self as NSString).length)
        let matches = regex.matches(in: self, options: [], range: range)
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let urlRange = Range(match.range(at: 1), in: self) else { continue }
            let url = String(self[urlRange])
            let textRange = Range(match.range(at: 2), in: self).map { String(self[$0]).cleanHTML() } ?? ""
            if predicate(url, textRange) {
                return url
            }
        }
        return nil
    }


    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    func firstHref(matchingSuffixes suffixes: [String]? = nil) -> String? {
        let pattern = "href=[\"']([^\"'>]+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(location: 0, length: (self as NSString).length)
        let matches = regex.matches(in: self, options: [], range: range)
        
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let raw = (self as NSString).substring(with: match.range(at: 1))
            let decoded = raw
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !decoded.isEmpty else { continue }
            
            if let suffixes = suffixes, !suffixes.isEmpty {
                let lower = decoded.lowercased()
                if suffixes.contains(where: { lower.hasSuffix($0.lowercased()) }) {
                    return decoded
                }
            } else {
                return decoded
            }
        }
        
        return nil
    }
}

extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        switch self {
        case .some(let value):
            return value.trimmedNonEmpty
        case .none:
            return nil
        }
    }
}
