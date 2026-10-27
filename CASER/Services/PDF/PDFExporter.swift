import CoreImage
import Foundation
import UIKit
import os.log

private let pdfLogger = Logger(subsystem: "com.caser.app", category: "PDFExporter")

enum LegalBriefStyle {
    static let inkPrimary = UIColor(red: 0.07, green: 0.09, blue: 0.16, alpha: 1.0)
    static let inkSecondary = UIColor(red: 0.27, green: 0.30, blue: 0.38, alpha: 1.0)
    static let inkMuted = UIColor(red: 0.45, green: 0.48, blue: 0.55, alpha: 1.0)
    static let ruleColor = UIColor(red: 0.18, green: 0.20, blue: 0.28, alpha: 1.0)
    static let hairlineColor = UIColor(red: 0.78, green: 0.80, blue: 0.85, alpha: 1.0)
    static let altRowFill = UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1.0)
    static let linkInk = UIColor(red: 0.10, green: 0.22, blue: 0.45, alpha: 1.0)

    enum PDFBranding {
        static let logoHeightBrief: CGFloat = 28
        static let logoHeightList: CGFloat = 22
        static let logoToStampGap: CGFloat = 4
        static let stampToContentGap: CGFloat = 10
        static let logoAspectRatio: CGFloat = 367.0 / 215.0

        static let printLogoImage: UIImage? = {
            guard let source = UIImage(named: "logo-header"),
                  let cgImage = source.cgImage else { return nil }

            let ciImage = CIImage(cgImage: cgImage)
            let extent = ciImage.extent
            let context = CIContext(options: nil)

            let inverted = ciImage.applyingFilter("CIColorInvert")
            let mask = inverted.applyingFilter("CIMaskToAlpha")
            guard let colorPlane = CIFilter(
                name: "CIConstantColorGenerator",
                parameters: ["inputColor": CIColor(color: LegalBriefStyle.inkPrimary)]
            )?.outputImage?.cropped(to: extent),
                  let blended = CIFilter(
                    name: "CIBlendWithAlphaMask",
                    parameters: [
                        kCIInputImageKey: colorPlane,
                        kCIInputBackgroundImageKey: CIImage.empty(),
                        kCIInputMaskImageKey: mask
                    ]
                  )?.outputImage,
                  let output = context.createCGImage(blended, from: extent) else { return nil }

            return UIImage(cgImage: output, scale: source.scale, orientation: source.imageOrientation)
        }()
    }

    static func serif(_ size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        let names: [String]
        switch (weight, italic) {
        case (.bold, true): names = ["TimesNewRomanPS-BoldItalicMT", "Times-BoldItalic"]
        case (.bold, false): names = ["TimesNewRomanPS-BoldMT", "Times-Bold"]
        case (_, true):      names = ["TimesNewRomanPS-ItalicMT", "Times-Italic"]
        default:             names = ["TimesNewRomanPSMT", "Times-Roman"]
        }
        for name in names {
            if let font = UIFont(name: name, size: size) { return font }
        }
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            .withDesign(.serif)?
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]])
        if let d = descriptor { return UIFont(descriptor: d, size: size) }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    static func sans(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    enum SingleCase {
        static let captionPartyFont    = LegalBriefStyle.serif(14, weight: .bold)
        static let captionVFont        = LegalBriefStyle.serif(12, weight: .regular, italic: true)
        static let captionMetaFont     = LegalBriefStyle.serif(11, weight: .regular)
        static let courtNameFont       = LegalBriefStyle.serif(12, weight: .regular)
        static let sectionLabelFont    = LegalBriefStyle.sans(9.5, weight: .bold)
        static let bodyFont            = LegalBriefStyle.serif(12)
        static let bodySmallFont       = LegalBriefStyle.serif(10.5)
        static let docketLabelFont     = LegalBriefStyle.sans(9.5, weight: .semibold)
        static let docketValueFont     = LegalBriefStyle.serif(11)
        static let linkLabelFont       = LegalBriefStyle.sans(9, weight: .semibold)
        static let linkFont            = LegalBriefStyle.serif(10)
        static let wordmarkFont        = LegalBriefStyle.sans(8.5, weight: .heavy)
        static let footerFont          = LegalBriefStyle.sans(8, weight: .regular)
        static let footerEmphasis      = LegalBriefStyle.sans(8, weight: .semibold)
    }

    enum ListReport {
        static let titleFont        = LegalBriefStyle.serif(16, weight: .bold)
        static let subtitleFont     = LegalBriefStyle.sans(10, weight: .regular)
        static let metaFont         = LegalBriefStyle.sans(9, weight: .regular)
        static let columnHeaderFont = LegalBriefStyle.sans(8, weight: .bold)
        static let rowFont          = LegalBriefStyle.serif(9.5)
        static let rowEmphasisFont  = LegalBriefStyle.serif(9.5, weight: .bold)
        static let linkFont         = LegalBriefStyle.serif(8.5)
        static let footerFont       = LegalBriefStyle.sans(8, weight: .regular)
    }
}

enum PDFPageLayout {
    static let size = CGSize(width: 612, height: 792)

    static let briefMargin: CGFloat = 72
    static let listMargin: CGFloat = 54
    static let topFooterReserve: CGFloat = 38
    static let topHeaderReserve: CGFloat = 52
    static let columnGutter: CGFloat = 6

    static func contentWidth(margin: CGFloat) -> CGFloat {
        size.width - margin * 2
    }

    static func bodyCutoffY(margin: CGFloat) -> CGFloat {
        size.height - margin - topFooterReserve
    }

    static func listColumnWidths(
        contentWidth: CGFloat = PDFPageLayout.contentWidth(margin: listMargin),
        gutter: CGFloat = columnGutter
    ) -> (court: CGFloat, docket: CGFloat, parties: CGFloat, filed: CGFloat) {
        let widths: (CGFloat, CGFloat, CGFloat, CGFloat) = (58, 104, 248, 76)
        let total = widths.0 + widths.1 + widths.2 + widths.3 + gutter * 3
        assert(abs(total - contentWidth) < 0.5,
               "List column widths must sum to content width (\(contentWidth)pt); got \(total)pt")
        return (court: widths.0, docket: widths.1, parties: widths.2, filed: widths.3)
    }
}

struct PDFExporter {

    private static var pageRect: CGRect { CGRect(origin: .zero, size: PDFPageLayout.size) }
    static let maximumListRows = 5_000

    private enum ExportJob: Sendable {
        case single(SingleCasePDFModel)
        case results(
            title: String,
            subtitle: String,
            filters: [String],
            rows: [SearchResultPDFModel]
        )
    }

    static func exportSingleCase(_ entry: CaseEntry) async -> URL? {
        let model = SingleCasePDFModel.make(from: entry)
        return await performExport(
            named: "CASER_Case_\(sanitizedFileComponent(entry.objectID))",
            job: .single(model)
        )
    }

    static func exportResults(_ results: [CaseEntry], query: String, filters: [String] = []) async -> URL? {
        guard results.count <= maximumListRows else { return nil }
        let rows = results.map { SearchResultPDFModel.make(from: $0) }
        return await performExport(
            named: "CASER_Search_\(sanitizedFileComponent(query))",
            job: .results(
                title: "Search Results",
                subtitle: query.isEmpty ? "All records" : "Query: \u{201C}\(query)\u{201D}",
                filters: filters,
                rows: rows
            )
        )
    }

    static func exportMatches(_ matches: [CaseMatch]) async -> URL? {
        guard matches.count <= maximumListRows else { return nil }
        let rows = matches.map { SearchResultPDFModel.make(from: $0) }
        let distinctKeywords = Set(matches.map { $0.keyword.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let subtitle: String
        if distinctKeywords.count == 1, let only = distinctKeywords.first {
            subtitle = "Keyword: \u{201C}\(only)\u{201D}"
        } else if distinctKeywords.isEmpty {
            subtitle = "All monitor matches"
        } else {
            subtitle = "\(distinctKeywords.count) keywords"
        }
        return await performExport(
            named: "CASER_Matches_\(timestampString())",
            job: .results(
                title: "Monitor Matches",
                subtitle: subtitle,
                filters: [],
                rows: rows
            )
        )
    }

    private static func performExport(named name: String, job: ExportJob) async -> URL? {
        let renderTask = Task.detached(priority: .userInitiated) { () -> URL? in
            guard !Task.isCancelled else { return nil }
            return writePDF(named: name) { context in
                guard !Task.isCancelled else { return }
                switch job {
                case .single(let model):
                    LegalBriefRenderer.renderSingleCase(model: model, context: context)
                case .results(let title, let subtitle, let filters, let rows):
                    LegalBriefRenderer.renderResultsList(
                        title: title,
                        subtitle: subtitle,
                        filters: filters,
                        rows: rows,
                        context: context
                    )
                }
            }
        }

        return await withTaskCancellationHandler {
            await renderTask.value
        } onCancel: {
            renderTask.cancel()
        }
    }

    private nonisolated static func writePDF(
        named name: String,
        drawing: (UIGraphicsPDFRendererContext) -> Void
    ) -> URL? {
        let fileName = "\(name)_\(timestampString()).pdf"
        guard let directory = exportsDirectory() else { return nil }
        let url = directory.appendingPathComponent(fileName)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: AppBranding.pdfMetadataCreator,
            kCGPDFContextAuthor as String: AppBranding.pdfMark,
            kCGPDFContextTitle as String: name
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        do {
            var renderingError: Error?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                do {
                    try renderer.writePDF(to: url) { context in
                        drawing(context)
                    }
                } catch {
                    renderingError = error
                }
            }
            if let renderingError { throw renderingError }
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            return url
        } catch {
            pdfLogger.error("PDF export failed: \(error)")
            return nil
        }
    }

    private nonisolated static var exportsURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PDFExports", isDirectory: true)
    }

    private nonisolated static func exportsDirectory() -> URL? {
        do {
            try FileManager.default.createDirectory(
                at: exportsURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            return exportsURL
        } catch {
            pdfLogger.error("Could not create PDF export directory: \(error)")
            return nil
        }
    }

    nonisolated static func removeLeftoverExports() {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: exportsURL)
        let tmp = fileManager.temporaryDirectory
        let leftovers = (try? fileManager.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        for url in leftovers where url.pathExtension.lowercased() == "pdf" {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func sanitizedFileComponent(_ text: String) -> String {
        let filtered = text.replacingOccurrences(of: "[^A-Za-z0-9\\-_]", with: "_", options: .regularExpression)
        let trimmed = filtered.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        return trimmed.isEmpty ? "Export" : String(trimmed.prefix(40))
    }

    private static func timestampString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    static var sharedPageSize: CGSize { PDFPageLayout.size }
    static var sharedBriefMargin: CGFloat { PDFPageLayout.briefMargin }
    static var sharedListMargin: CGFloat { PDFPageLayout.listMargin }
    static var sharedTopFooterReserve: CGFloat { PDFPageLayout.topFooterReserve }
    static var sharedTopHeaderReserve: CGFloat { PDFPageLayout.topHeaderReserve }
}

struct SingleCasePDFModel: Sendable {
    let captionLine: String
    let captionParties: (plaintiff: String, defendant: String)?
    let courtFullName: String
    let docketNumber: String?
    let filedDateText: String?
    let natureOfSuit: String?
    let causeText: String?
    let citation: String?
    let summary: String?
    let parties: [String]
    let subjects: [String]
    let categories: [String]
    let docketURL: URL?
    let documentURL: URL?
    let documentZipURL: URL?
    let pacerURL: URL?

    var anyDocumentLinkAvailable: Bool {
        docketURL != nil || documentURL != nil || documentZipURL != nil
    }

    static func make(from entry: CaseEntry) -> SingleCasePDFModel {
        let rawTitle = (entry.displayTitle.cleanHTML().trimmedNonEmpty ?? "Untitled Case")
        let parsedCaption = PDFTextUtilities.parsePartiesCaption(rawTitle)

        let parties = entry.parties
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let docketURL = URLValidator.safeCourtURL(entry.link.trimmedNonEmpty ?? "")
        let documentURL: URL? = {
            guard let raw = entry.primaryDocumentURL?.trimmedNonEmpty,
                  let url = URLValidator.safeCourtURL(raw) else { return nil }
            if let docket = docketURL, url.absoluteString.caseInsensitiveCompare(docket.absoluteString) == .orderedSame {
                return nil
            }
            return url
        }()

        let zipURL: URL? = {
            guard let raw = entry.govinfoZipUrl?.trimmedNonEmpty,
                  let url = URLValidator.safeCourtURL(raw) else { return nil }
            if let doc = documentURL, url.absoluteString.caseInsensitiveCompare(doc.absoluteString) == .orderedSame { return nil }
            return url
        }()

        let pacerURL: URL? = PDFTextUtilities.derivePACERURL(from: entry, validatedDocket: docketURL)

        let courtName = entry.courtName?.trimmedNonEmpty ?? entry.courtId.uppercased()
        let docketNumber = entry.displayCaseNumber?.trimmedNonEmpty
        let summary: String? = {
            let s = entry.cleanedSummary
            if s == CaseEntry.summaryPlaceholder { return nil }
            return s.trimmedNonEmpty
        }()

        return SingleCasePDFModel(
            captionLine: rawTitle,
            captionParties: parsedCaption,
            courtFullName: PDFTextUtilities.expandCourtName(courtName),
            docketNumber: docketNumber,
            filedDateText: entry.pubDate.map {
                let df = DateFormatter()
                df.dateStyle = .long
                df.timeStyle = .none
                return df.string(from: $0)
            },
            natureOfSuit: entry.modsCourtType?.trimmedNonEmpty?.capitalized
                ?? entry.caseType?.trimmedNonEmpty?.capitalized,
            causeText: nil,
            citation: entry.displayCitation,
            summary: summary,
            parties: parties,
            subjects: entry.displaySubjects,
            categories: entry.displayCategories,
            docketURL: docketURL,
            documentURL: documentURL,
            documentZipURL: zipURL,
            pacerURL: pacerURL
        )
    }
}

struct SearchResultPDFModel: Sendable {
    let parties: String
    let courtAbbrev: String
    let courtFullName: String
    let docketNumber: String?
    let citation: String?
    let filedDate: Date?
    let link: URL?
    let summarySnippet: String?
    let keyword: String?

    static func make(from entry: CaseEntry) -> SearchResultPDFModel {
        let title = entry.displayTitle.cleanHTML().trimmedNonEmpty ?? "Untitled Case"
        let parsed = PDFTextUtilities.parsePartiesCaption(title)
        let partiesText: String
        if let parsed { partiesText = "\(parsed.plaintiff) v. \(parsed.defendant)" }
        else { partiesText = title }

        let fullCourt = entry.courtName?.trimmedNonEmpty ?? entry.courtId.uppercased()
        let abbrev = PDFTextUtilities.courtAbbreviation(courtId: entry.courtId, fullName: fullCourt)
        let link: URL? = {
            guard let raw = entry.link.trimmedNonEmpty else { return nil }
            return URLValidator.safeCourtURL(raw)
        }()

        let snippet: String? = {
            let s = entry.cleanedSummary
            if s == CaseEntry.summaryPlaceholder { return nil }
            return s.trimmedNonEmpty
        }()

        return SearchResultPDFModel(
            parties: partiesText,
            courtAbbrev: abbrev,
            courtFullName: fullCourt,
            docketNumber: entry.displayCaseNumber?.trimmedNonEmpty,
            citation: entry.displayCitation,
            filedDate: entry.pubDate,
            link: link,
            summarySnippet: snippet,
            keyword: nil
        )
    }

    static func make(from match: CaseMatch) -> SearchResultPDFModel {
        let title = match.title.cleanHTML().trimmedNonEmpty ?? "Untitled Case"
        let parsed = PDFTextUtilities.parsePartiesCaption(title)
        let partiesText: String
        if let parsed { partiesText = "\(parsed.plaintiff) v. \(parsed.defendant)" }
        else { partiesText = title }

        let fullCourt = match.courtName?.trimmedNonEmpty ?? match.courtId.uppercased()
        let abbrev = PDFTextUtilities.courtAbbreviation(courtId: match.courtId, fullName: fullCourt)
        let link: URL? = {
            guard let raw = match.link.trimmedNonEmpty else { return nil }
            return URLValidator.safeCourtURL(raw)
        }()

        let snippet = match.matchedText.cleanHTML().trimmedNonEmpty

        return SearchResultPDFModel(
            parties: partiesText,
            courtAbbrev: abbrev,
            courtFullName: fullCourt,
            docketNumber: match.caseNumber?.trimmedNonEmpty,
            citation: match.citation?.sanitizedCitationText(),
            filedDate: match.pubDate ?? match.createdAt,
            link: link,
            summarySnippet: snippet,
            keyword: match.keyword.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
