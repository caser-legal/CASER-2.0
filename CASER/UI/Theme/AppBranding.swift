import Foundation

enum AppBranding {
    static let fullName = "Case Alerts & Search of Electronic Records"

    static let shortName = "Case Search & Alerts by CASER"

    static let aka = "aka \(shortName)"

    static let legalReference = "\(fullName) (\(aka))"

    static let supportEmail = ["caserlegal", "proton.me"].joined(separator: "@")

    static let pdfMark = "CASER"
    static let pdfDomain = "caserlegal.com"

    static func pdfProvenanceLine(generatedOn date: Date = Date()) -> String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none
        return "\(pdfMark) · \(pdfDomain) · Prepared \(df.string(from: date))"
    }

    static let pdfMetadataCreator = "\(pdfMark) (\(pdfDomain))"
}
