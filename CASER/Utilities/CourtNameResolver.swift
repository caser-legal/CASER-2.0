import Foundation

func resolveCourtName(courtId: String, explicitName: String?) -> String {
    if let sanitizedExplicit = sanitizedExplicitCourtName(explicitName) {
        return sanitizedExplicit
    }

    let key = courtId.lowercased()
    let normalizedKey = key.replacingOccurrences(of: "uscourts-", with: "")
    let names: [String: String] = [
        "deb": "Delaware Bankruptcy",
        "nysd": "S.D. New York",
        "cacd": "C.D. California",
        "txnd": "N.D. Texas",
        "flsd": "S.D. Florida",
        "ilnd": "N.D. Illinois",
        "almb": "M.D. Alabama Bankruptcy",
        "azb": "Arizona Bankruptcy",
        "cacb": "C.D. California Bankruptcy"
    ]

    if let mapped = names[normalizedKey] { return mapped }

    if let generated = generatedCourtName(from: normalizedKey) {
        return generated
    }

    let fallback = normalizedKey.replacingOccurrences(of: "-", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return fallback.isEmpty ? courtId.uppercased() : fallback.capitalized
}

private func sanitizedExplicitCourtName(_ explicitName: String?) -> String? {
    guard let explicit = explicitName?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty else {
        return nil
    }
    let lower = explicit.lowercased()
    let invalidTokens = ["uscourts", "us courts", "uscourt"]
    if invalidTokens.contains(where: { lower.contains($0) }) {
        return nil
    }
    if lower == "court" || lower == "federal appellate court" {
        return nil
    }
    return explicit
}

private func generatedCourtName(from key: String) -> String? {
    guard key.count >= 3 else { return nil }
    let stateCode = String(key.prefix(2)).uppercased()
    let suffix = String(key.dropFirst(2))

    guard let stateName = StateAbbreviations.name(for: stateCode) else { return nil }

    let descriptor = suffix.lowercased()

    let (region, isBankruptcy) = regionDescription(from: descriptor)

    if isBankruptcy {
        if let region {
            return "\(region) of \(stateName) Bankruptcy Court"
        }
        return "\(stateName) Bankruptcy Court"
    }

    if let region {
        return "\(region) of \(stateName) District Court"
    }

    return "\(stateName) District Court"
}

private func regionDescription(from descriptor: String) -> (String?, Bool) {
    var raw = descriptor
    var isBankruptcy = false
    if raw.hasSuffix("b") {
        isBankruptcy = true
        raw.removeLast()
    }

    let regions: [String: String] = [
        "nd": "Northern District",
        "n": "Northern District",
        "sd": "Southern District",
        "s": "Southern District",
        "ed": "Eastern District",
        "e": "Eastern District",
        "wd": "Western District",
        "w": "Western District",
        "md": "Middle District",
        "m": "Middle District",
        "cd": "Central District",
        "c": "Central District"
    ]

    return (regions[raw], isBankruptcy)
}
