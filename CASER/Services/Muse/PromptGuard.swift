import Foundation

enum PromptGuard {
    enum Decision {
        case allowed(String)
        case blocked(String)
    }
    
    private static let maxInputLength = 2000
    private static let maxPreparedPromptLength = 8000
    
    private static let suspiciousPatterns: [NSRegularExpression] = {
        let patterns = [
            #"(?i)(?:^|[.!?]\s+)(?:please\s+)?(?:ignore|disregard|forget|reset|override) (?:all |the |your )?(?:previous |prior |above |earlier )?(?:instructions|guardrails|rules|guidelines|prompts?)\b"#,
            #"(?i)(?:^|[.!?]\s+)(?:reveal|show|print|repeat|output|leak) (?:me )?(?:the )?system (?:prompt|instructions?)\b"#,
            #"(?i)\byou are (?:now )?(?:jailbroken|my servant|in developer mode|dan\b)"#,
            #"(?i)\bbegin prompt injection\b"#
        ]

        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()
    
    private static let highEntropyChunk: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"[A-Za-z0-9+/]{200,}={0,2}"#, options: [])
    }()
    
    static func validateUntrustedField(_ raw: String) -> Decision {
        let sanitized = sanitizeForModel(raw)
        let range = NSRange(location: 0, length: sanitized.utf16.count)

        let embeddedPatterns = [
            #"(?i)(?:ignore|disregard|forget|reset|override) (?:all |the |your )?(?:previous |prior |above |earlier )?(?:instructions|guardrails|rules|guidelines|prompts?)\b"#,
            #"(?i)(?:reveal|show|print|repeat|output|leak) (?:me )?(?:the )?system (?:prompt|instructions?)\b"#,
            #"(?i)\byou are (?:now )?(?:jailbroken|my servant|in developer mode|dan\b)"#,
            #"(?i)\bbegin prompt injection\b"#
        ]

        for pattern in embeddedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            if regex.firstMatch(in: sanitized, options: [], range: range) != nil {
                return .blocked("I can't help with that. Let's stick to the legal research question.")
            }
        }

        return .allowed(sanitized)
    }

    static func validateUserInput(_ raw: String) -> Decision {
        let sanitized = sanitizeForModel(raw)
        let range = NSRange(location: 0, length: sanitized.utf16.count)
        
        for regex in suspiciousPatterns {
            if regex.firstMatch(in: sanitized, options: [], range: range) != nil {
                return .blocked("I can't help with that. Let's stick to the legal research question.")
            }
        }
        
        if let entropyRegex = highEntropyChunk,
           entropyRegex.firstMatch(in: sanitized, options: [], range: range) != nil {
            return .blocked("That looks like encoded content I can't process. Please rephrase your request.")
        }
        
        return .allowed(sanitized)
    }
    
    static func sanitizeForModel(_ raw: String) -> String {
        normalize(raw, maximumLength: maxInputLength)
    }

    static func sanitizePreparedModelPrompt(_ raw: String) -> String {
        normalize(raw, maximumLength: maxPreparedPromptLength)
    }

    private static func normalize(_ raw: String, maximumLength: Int) -> String {
        var normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.count > maximumLength {
            normalized = String(normalized.prefix(maximumLength))
        }

        return normalized
    }
}
