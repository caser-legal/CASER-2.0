import CoreText
import Foundation
import UIKit

enum LegalBriefRenderer {

    private static let docketLabelWidth: CGFloat = 130
    private static let docketRowPaddingV: CGFloat = 4
    private static let docketRowMinHeight: CGFloat = 14

    private static func measuredTextHeight(_ text: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil)
        return ceil(bounding.height)
    }

    private static func footerCutoffY(margin: CGFloat = PDFPageLayout.briefMargin) -> CGFloat {
        PDFPageLayout.bodyCutoffY(margin: margin)
    }

    private static func ensureVerticalRoom(needed: CGFloat,
                                           cursorY: CGFloat,
                                           margin: CGFloat,
                                           page: inout Int,
                                           model: SingleCasePDFModel,
                                           context: UIGraphicsPDFRendererContext) -> CGFloat {
        if cursorY + needed > footerCutoffY(margin: margin) {
            page += 1
            return beginSingleCasePage(model: model, page: page, isFirst: false, context: context)
        }
        return cursorY
    }

    static func renderSingleCase(model: SingleCasePDFModel, context: UIGraphicsPDFRendererContext) {
        var page = 1
        var cursorY = beginSingleCasePage(model: model, page: page, isFirst: true, context: context)

        let docketRows = buildDocketRows(model: model)
        if !docketRows.isEmpty {
            cursorY = ensureVerticalRoom(needed: estimateDocketRowsHeight(docketRows) + 28,
                                         cursorY: cursorY, margin: PDFPageLayout.briefMargin,
                                         page: &page, model: model, context: context)
            cursorY = drawSectionLabel("DOCKET INFORMATION", at: cursorY)
            cursorY += 6
            cursorY = drawDocketRows(docketRows, startingAt: cursorY)
            cursorY += 18
        }

        if let summary = model.summary {
            cursorY = ensureVerticalRoom(needed: 36, cursorY: cursorY, margin: PDFPageLayout.briefMargin,
                                         page: &page, model: model, context: context)
            cursorY = drawSectionLabel("CASE SUMMARY", at: cursorY)
            cursorY += 8
            cursorY = drawJustifiedBody(summary,
                                        startingAt: cursorY,
                                        page: &page,
                                        model: model,
                                        context: context)
            cursorY += 18
        }

        if model.parties.count > 2 || (model.parties.count > 0 && model.captionParties == nil) {
            let estimated = CGFloat(model.parties.count) * 16 + 30
            cursorY = ensureVerticalRoom(needed: estimated, cursorY: cursorY, margin: PDFPageLayout.briefMargin,
                                         page: &page, model: model, context: context)
            cursorY = drawSectionLabel("PARTIES OF RECORD", at: cursorY)
            cursorY += 6
            for party in model.parties {
                cursorY = ensureVerticalRoom(needed: 18, cursorY: cursorY, margin: PDFPageLayout.briefMargin,
                                             page: &page, model: model, context: context)
                cursorY = drawDocketBulletRow(party, startingAt: cursorY)
            }
            cursorY += 16
        }

        let linkRows = buildLinkRows(model: model, includePACER: false)
        if !linkRows.isEmpty {
            let linkSectionHeight = linkRows.reduce(CGFloat(0)) { partial, row in
                partial + estimateLinkRowHeight(label: row.label, url: row.url)
            } + 30
            cursorY = ensureVerticalRoom(needed: linkSectionHeight, cursorY: cursorY,
                                         margin: PDFPageLayout.briefMargin, page: &page, model: model, context: context)
            cursorY = drawSectionLabel("DOCUMENTS & LINKS", at: cursorY)
            cursorY += 6
            for row in linkRows {
                let rowHeight = estimateLinkRowHeight(label: row.label, url: row.url)
                cursorY = ensureVerticalRoom(needed: rowHeight, cursorY: cursorY, margin: PDFPageLayout.briefMargin,
                                             page: &page, model: model, context: context)
                cursorY = drawLinkRow(label: row.label, url: row.url, startingAt: cursorY, context: context)
            }
            cursorY += 16
        }

        if let pacer = model.pacerURL {
            let pacerNote = "Access to documents on PACER requires a registered account and may incur per-page fees set by the Administrative Office of the U.S. Courts."
            let pacerBlockHeight = 30
                + estimateLinkRowHeight(label: "Docket Report (PACER)", url: pacer)
                + 8
                + estimateWrappedTextHeight(
                    pacerNote,
                    font: LegalBriefStyle.SingleCase.bodySmallFont,
                    width: singleCaseContentWidth(),
                    lineSpacing: 3)
            cursorY = ensureVerticalRoom(needed: pacerBlockHeight, cursorY: cursorY, margin: PDFPageLayout.briefMargin,
                                         page: &page, model: model, context: context)
            cursorY = drawSectionLabel("PACER REFERENCE", at: cursorY)
            cursorY += 6
            cursorY = drawLinkRow(label: "Docket Report (PACER)", url: pacer, startingAt: cursorY, context: context)
            cursorY += 8
            let note = pacerNote
            cursorY = drawJustifiedBody(note,
                                        startingAt: cursorY,
                                        page: &page,
                                        model: model,
                                        context: context,
                                        font: LegalBriefStyle.SingleCase.bodySmallFont,
                                        ink: LegalBriefStyle.inkSecondary)
            cursorY += 12
        }

        if !model.subjects.isEmpty {
            cursorY = ensureVerticalRoom(needed: 60, cursorY: cursorY, margin: PDFPageLayout.briefMargin,
                                         page: &page, model: model, context: context)
            cursorY = drawSectionLabel("SUBJECT MATTER", at: cursorY)
            cursorY += 6
            let joined = model.subjects.joined(separator: " \u{2022} ")
            cursorY = drawJustifiedBody(joined, startingAt: cursorY, page: &page, model: model, context: context,
                                        font: LegalBriefStyle.SingleCase.bodySmallFont,
                                        ink: LegalBriefStyle.inkSecondary)
            cursorY += 12
        }
        if !model.categories.isEmpty {
            cursorY = ensureVerticalRoom(needed: 60, cursorY: cursorY, margin: PDFPageLayout.briefMargin,
                                         page: &page, model: model, context: context)
            cursorY = drawSectionLabel("CATEGORIES", at: cursorY)
            cursorY += 6
            let joined = model.categories.joined(separator: " \u{2022} ")
            cursorY = drawJustifiedBody(joined, startingAt: cursorY, page: &page, model: model, context: context,
                                        font: LegalBriefStyle.SingleCase.bodySmallFont,
                                        ink: LegalBriefStyle.inkSecondary)
        }

        _ = page
    }

    private static func beginSingleCasePage(model: SingleCasePDFModel, page: Int, isFirst: Bool, context: UIGraphicsPDFRendererContext) -> CGFloat {
        context.beginPage()
        let margin = PDFExporter.sharedBriefMargin
        let pageW = PDFExporter.sharedPageSize.width
        let contentW = pageW - margin * 2
        var y = margin
        y = drawPageHeader(
            at: y,
            margin: margin,
            contentWidth: contentW,
            pageWidth: pageW,
            logoHeight: LegalBriefStyle.PDFBranding.logoHeightBrief,
            drawSeparator: true
        )

        if isFirst {
            y = drawCaptionBlock(model: model, startingAt: y, contentWidth: contentW, margin: margin)
        } else {
            y = drawContinuationHeader(model: model, startingAt: y, contentWidth: contentW, margin: margin, page: page)
        }
        drawFooter(page: page, leftLabel: "\(AppBranding.pdfMark) · \(AppBranding.pdfDomain)")
        return y
    }

    private static func drawPageHeader(
        at startY: CGFloat,
        margin: CGFloat,
        contentWidth: CGFloat,
        pageWidth: CGFloat,
        logoHeight: CGFloat,
        drawSeparator: Bool = false
    ) -> CGFloat {
        var y = startY
        let branding = LegalBriefStyle.PDFBranding.self
        let logoWidth = logoHeight * branding.logoAspectRatio

        if let logo = branding.printLogoImage {
            let logoRect = CGRect(x: margin + (contentWidth - logoWidth) / 2, y: y, width: logoWidth, height: logoHeight)
            logo.draw(in: logoRect)
        }
        y += logoHeight + branding.logoToContentGap

        if drawSeparator {
            drawHorizontalRule(
                y: y,
                x1: margin,
                x2: pageWidth - margin,
                color: LegalBriefStyle.inkMuted.withAlphaComponent(0.15),
                width: 0.4
            )
            y += 4
        }

        return y
    }

    private static func drawCaptionBlock(model: SingleCasePDFModel, startingAt y: CGFloat, contentWidth: CGFloat, margin: CGFloat) -> CGFloat {
        var cursor = y + 4
        let pageW = PDFExporter.sharedPageSize.width

        drawHorizontalRule(y: cursor, x1: margin, x2: pageW - margin, color: LegalBriefStyle.ruleColor, width: 1.0)
        drawHorizontalRule(y: cursor + 2.2, x1: margin, x2: pageW - margin, color: LegalBriefStyle.ruleColor, width: 0.4)
        cursor += 14

        if let parties = model.captionParties {
            cursor = drawCenteredCaptionParties(plaintiff: parties.plaintiff, defendant: parties.defendant,
                                                startingAt: cursor, margin: margin, contentWidth: contentWidth)
        } else {
            cursor = drawCenteredText(model.captionLine.localizedCapitalized,
                                      font: LegalBriefStyle.SingleCase.captionPartyFont,
                                      ink: LegalBriefStyle.inkPrimary,
                                      startingAt: cursor, margin: margin, contentWidth: contentWidth,
                                      lineSpacing: 2)
        }

        cursor += 6

        if let docket = model.docketNumber {
            cursor = drawCenteredText("Case No. \(docket)",
                                      font: LegalBriefStyle.SingleCase.captionMetaFont,
                                      ink: LegalBriefStyle.inkPrimary,
                                      startingAt: cursor, margin: margin, contentWidth: contentWidth)
            cursor += 3
        }

        cursor = drawCenteredText(model.courtFullName,
                                  font: LegalBriefStyle.SingleCase.courtNameFont,
                                  ink: LegalBriefStyle.inkPrimary,
                                  startingAt: cursor, margin: margin, contentWidth: contentWidth)

        if let cite = model.citation {
            cursor += 3
            cursor = drawCenteredText(cite,
                                      font: LegalBriefStyle.SingleCase.captionMetaFont,
                                      ink: LegalBriefStyle.inkSecondary,
                                      startingAt: cursor, margin: margin, contentWidth: contentWidth)
        }

        cursor += 12
        drawHorizontalRule(y: cursor, x1: margin, x2: pageW - margin, color: LegalBriefStyle.ruleColor, width: 0.6)
        cursor += 22
        return cursor
    }

    private static func drawContinuationHeader(model: SingleCasePDFModel, startingAt y: CGFloat, contentWidth: CGFloat, margin: CGFloat, page: Int) -> CGFloat {
        let pageW = PDFExporter.sharedPageSize.width
        var cursor = y
        let title: String
        if let parties = model.captionParties {
            title = "\(parties.plaintiff) v. \(parties.defendant)"
        } else {
            title = model.captionLine
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.serif(10.5, weight: .regular, italic: true),
            .foregroundColor: LegalBriefStyle.inkSecondary
        ]
        (title as NSString).draw(at: CGPoint(x: margin, y: cursor), withAttributes: attrs)
        if let docket = model.docketNumber {
            let right = "Case No. \(docket)"
            let rightAttrs: [NSAttributedString.Key: Any] = [
                .font: LegalBriefStyle.serif(10.5, weight: .regular),
                .foregroundColor: LegalBriefStyle.inkSecondary
            ]
            let size = (right as NSString).size(withAttributes: rightAttrs)
            (right as NSString).draw(at: CGPoint(x: pageW - margin - size.width, y: cursor), withAttributes: rightAttrs)
        }
        cursor += 18
        drawHorizontalRule(y: cursor, x1: margin, x2: pageW - margin, color: LegalBriefStyle.hairlineColor, width: 0.4)
        cursor += 14
        return cursor
    }

    private static func buildDocketRows(model: SingleCasePDFModel) -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let filed = model.filedDateText { rows.append(("Filed", filed)) }
        rows.append(("Court", model.courtFullName))
        if let docket = model.docketNumber { rows.append(("Docket Number", docket)) }
        if let nos = model.natureOfSuit { rows.append(("Nature of Suit", nos)) }
        if let cause = model.causeText { rows.append(("Cause", cause)) }
        if let cite = model.citation { rows.append(("Citation", cite)) }
        return rows
    }

    private static func docketRowAttributes() -> (label: [NSAttributedString.Key: Any], value: [NSAttributedString.Key: Any]) {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.SingleCase.docketLabelFont,
            .foregroundColor: LegalBriefStyle.inkSecondary,
            .kern: 0.4
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.SingleCase.docketValueFont,
            .foregroundColor: LegalBriefStyle.inkPrimary
        ]
        return (labelAttrs, valueAttrs)
    }

    private static func estimateDocketRowHeight(label: String, value: String, contentWidth: CGFloat) -> CGFloat {
        let attrs = docketRowAttributes()
        let valueW = contentWidth - docketLabelWidth
        let valueH = measuredTextHeight(value, width: valueW, attributes: attrs.value)
        let labelH = measuredTextHeight(label.uppercased(), width: docketLabelWidth, attributes: attrs.label)
        return max(valueH, labelH, docketRowMinHeight) + docketRowPaddingV
    }

    private static func estimateDocketRowsHeight(_ rows: [(String, String)]) -> CGFloat {
        let contentW = PDFPageLayout.contentWidth(margin: PDFPageLayout.briefMargin)
        return rows.reduce(0) { partial, row in
            partial + estimateDocketRowHeight(label: row.0, value: row.1, contentWidth: contentW)
        }
    }

    private static func drawDocketRows(_ rows: [(String, String)], startingAt y: CGFloat) -> CGFloat {
        var cursor = y
        let margin = PDFPageLayout.briefMargin
        let contentW = PDFPageLayout.contentWidth(margin: margin)
        let valueW = contentW - docketLabelWidth
        let attrs = docketRowAttributes()

        for (i, row) in rows.enumerated() {
            let rowH = estimateDocketRowHeight(label: row.0, value: row.1, contentWidth: contentW)
            let bandH = rowH - docketRowPaddingV

            if i.isMultiple(of: 2) {
                let band = CGRect(x: margin - 4, y: cursor - 2, width: contentW + 8, height: bandH + 4)
                let path = UIBezierPath(rect: band)
                LegalBriefStyle.altRowFill.setFill()
                path.fill()
            }

            (row.0.uppercased() as NSString).draw(at: CGPoint(x: margin, y: cursor),
                                                  withAttributes: attrs.label)
            let valueRect = CGRect(x: margin + docketLabelWidth, y: cursor - 1, width: valueW, height: bandH)
            (row.1 as NSString).draw(in: valueRect, withAttributes: attrs.value)
            cursor += rowH
        }
        return cursor
    }

    private static func drawDocketBulletRow(_ text: String, startingAt y: CGFloat) -> CGFloat {
        let margin = PDFExporter.sharedBriefMargin
        let pageW = PDFExporter.sharedPageSize.width
        let contentW = pageW - margin * 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.SingleCase.bodyFont,
            .foregroundColor: LegalBriefStyle.inkPrimary
        ]
        let bullet = "  \u{2022}  "
        let combined = bullet + text
        let bounding = (combined as NSString).boundingRect(
            with: CGSize(width: contentW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil)
        (combined as NSString).draw(in: CGRect(x: margin, y: y, width: contentW, height: ceil(bounding.height)),
                                    withAttributes: attrs)
        return y + ceil(bounding.height) + 4
    }

    private static func buildLinkRows(model: SingleCasePDFModel, includePACER: Bool) -> [(label: String, url: URL)] {
        var rows: [(String, URL)] = []
        if let d = model.docketURL { rows.append(("Docket / Case Listing", d)) }
        if let doc = model.documentURL { rows.append(("Primary Document", doc)) }
        if let z = model.documentZipURL { rows.append(("ZIP Archive (GovInfo)", z)) }
        if includePACER, let p = model.pacerURL { rows.append(("PACER Docket Report", p)) }
        return rows
    }

    private static let singleCaseLinkLabelWidth: CGFloat = 160

    private static func singleCaseContentWidth() -> CGFloat {
        PDFPageLayout.contentWidth(margin: PDFPageLayout.briefMargin)
    }

    private static func listContentWidth() -> CGFloat {
        PDFPageLayout.contentWidth(margin: PDFPageLayout.listMargin)
    }

    private static func estimateLinkRowHeight(label: String, url: URL) -> CGFloat {
        let contentW = singleCaseContentWidth()
        let urlHeight = estimateLinkTextHeight(
            fittedLinkText(url, font: LegalBriefStyle.SingleCase.linkFont, width: contentW - singleCaseLinkLabelWidth),
            font: LegalBriefStyle.SingleCase.linkFont,
            width: contentW - singleCaseLinkLabelWidth)
        let labelH = LegalBriefStyle.SingleCase.linkLabelFont.lineHeight
        return max(urlHeight, labelH, 14) + 4
    }

    private static func drawLinkRow(label: String, url: URL, startingAt y: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        let margin = PDFExporter.sharedBriefMargin
        let contentW = singleCaseContentWidth()
        let labelW = singleCaseLinkLabelWidth

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.SingleCase.linkLabelFont,
            .foregroundColor: LegalBriefStyle.inkSecondary,
            .kern: 0.4
        ]

        (label.uppercased() as NSString).draw(at: CGPoint(x: margin, y: y),
                                              withAttributes: labelAttrs)

        let urlHeight = drawHyperlinkedText(
            fittedLinkText(url, font: LegalBriefStyle.SingleCase.linkFont, width: contentW - labelW),
            url: url,
            origin: CGPoint(x: margin + labelW, y: y),
            width: contentW - labelW,
            font: LegalBriefStyle.SingleCase.linkFont,
            context: context)
        let labelH = LegalBriefStyle.SingleCase.linkLabelFont.lineHeight
        return y + max(urlHeight, labelH, 14) + 4
    }

    @discardableResult
    private static func drawSectionLabel(_ text: String, at y: CGFloat) -> CGFloat {
        let margin = PDFExporter.sharedBriefMargin
        let pageW = PDFExporter.sharedPageSize.width
        let attrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.SingleCase.sectionLabelFont,
            .foregroundColor: LegalBriefStyle.inkPrimary,
            .kern: 1.2
        ]
        (text as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)
        let lineY = y + LegalBriefStyle.SingleCase.sectionLabelFont.lineHeight + 2
        drawHorizontalRule(y: lineY, x1: margin, x2: pageW - margin, color: LegalBriefStyle.hairlineColor, width: 0.4)
        return lineY + 2
    }

    private static func drawJustifiedBody(_ text: String,
                                          startingAt y: CGFloat,
                                          page: inout Int,
                                          model: SingleCasePDFModel,
                                          context: UIGraphicsPDFRendererContext,
                                          font: UIFont = LegalBriefStyle.SingleCase.bodyFont,
                                          ink: UIColor = LegalBriefStyle.inkPrimary) -> CGFloat {
        let margin = PDFExporter.sharedBriefMargin
        let pageW = PDFExporter.sharedPageSize.width
        let contentW = pageW - margin * 2
        let para = NSMutableParagraphStyle()
        para.alignment = .justified
        para.lineSpacing = 3
        para.hyphenationFactor = 0.4
        para.lineBreakMode = .byWordWrapping

        let attrString = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: ink,
            .paragraphStyle: para
        ])

        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        var range = CFRange(location: 0, length: 0)
        var cursorY = y

        while range.location < attrString.length {
            let availableHeight = footerCutoffY() - cursorY
            if availableHeight < 24 {
                page += 1
                cursorY = beginSingleCasePage(model: model, page: page, isFirst: false, context: context)
                continue
            }

            let path = CGMutablePath()
            let pageHeight = PDFExporter.sharedPageSize.height
            let flippedY = pageHeight - cursorY - availableHeight
            path.addRect(CGRect(x: margin, y: flippedY, width: contentW, height: availableHeight))

            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: range.location, length: 0), path, nil)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length == 0 {
                page += 1
                cursorY = beginSingleCasePage(model: model, page: page, isFirst: false, context: context)
                continue
            }

            if let cg = UIGraphicsGetCurrentContext() {
                cg.saveGState()
                cg.translateBy(x: 0, y: pageHeight)
                cg.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, cg)
                cg.restoreGState()
            }

            let lineSpacing = para.lineSpacing
            var consumed: CGFloat = 0
            if visibleRange.length > 0 {
                let visibleSubstring = attrString.attributedSubstring(
                    from: NSRange(location: visibleRange.location, length: visibleRange.length))
                let bounds = visibleSubstring.boundingRect(
                    with: CGSize(width: contentW, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil)
                consumed = ceil(bounds.height)
            } else if let lines = CTFrameGetLines(frame) as? [CTLine], let lastLine = lines.last {
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                _ = CTLineGetTypographicBounds(lastLine, &ascent, &descent, &leading)
                consumed = ceil(ascent + descent + leading + lineSpacing)
            }
            cursorY += max(consumed, font.lineHeight + lineSpacing)

            range.location += visibleRange.length
        }

        return cursorY
    }

    static func renderResultsList(title: String,
                                  subtitle: String,
                                  filters: [String],
                                  rows: [SearchResultPDFModel],
                                  context: UIGraphicsPDFRendererContext) {
        var page = 1
        var cursor = beginListPage(title: title, subtitle: subtitle, filters: filters,
                                   totalRows: rows.count, page: page, isFirst: true, context: context)

        if rows.isEmpty {
            let margin = PDFExporter.sharedListMargin
            let pageW = PDFExporter.sharedPageSize.width
            let contentW = pageW - margin * 2
            let attrs: [NSAttributedString.Key: Any] = [
                .font: LegalBriefStyle.serif(11, italic: true),
                .foregroundColor: LegalBriefStyle.inkMuted
            ]
            ("No records available for this report." as NSString).draw(
                in: CGRect(x: margin, y: cursor + 8, width: contentW, height: 32),
                withAttributes: attrs)
            _ = page
            return
        }

        cursor = drawListColumnHeader(at: cursor)

        for (idx, row) in rows.enumerated() {
            let rowHeight = estimateListRowHeight(row)
            if cursor + rowHeight > footerCutoffY(margin: PDFPageLayout.listMargin) {
                page += 1
                cursor = beginListPage(title: title, subtitle: subtitle, filters: filters,
                                       totalRows: rows.count, page: page, isFirst: false, context: context)
                cursor = drawListColumnHeader(at: cursor)
            }
            drawListRow(row, index: idx, startingAt: cursor, context: context)
            cursor += rowHeight
        }

        _ = page
    }

    private static func beginListPage(title: String, subtitle: String, filters: [String],
                                      totalRows: Int, page: Int, isFirst: Bool,
                                      context: UIGraphicsPDFRendererContext) -> CGFloat {
        context.beginPage()
        let margin = PDFExporter.sharedListMargin
        let pageW = PDFExporter.sharedPageSize.width
        let contentW = pageW - margin * 2
        var cursor = margin
        cursor = drawPageHeader(
            at: cursor,
            margin: margin,
            contentWidth: contentW,
            pageWidth: pageW,
            logoHeight: LegalBriefStyle.PDFBranding.logoHeightList
        )

        if isFirst {
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: LegalBriefStyle.ListReport.titleFont,
                .foregroundColor: LegalBriefStyle.inkPrimary
            ]
            ("CASER \u{2014} \(title)" as NSString).draw(at: CGPoint(x: margin, y: cursor), withAttributes: titleAttrs)
            cursor += LegalBriefStyle.ListReport.titleFont.lineHeight + 2

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: LegalBriefStyle.ListReport.subtitleFont,
                .foregroundColor: LegalBriefStyle.inkSecondary
            ]
            (subtitle as NSString).draw(at: CGPoint(x: margin, y: cursor), withAttributes: subAttrs)
            cursor += LegalBriefStyle.ListReport.subtitleFont.lineHeight + 4

            var metaBits: [String] = ["\(totalRows) result\(totalRows == 1 ? "" : "s")"]
            if !filters.isEmpty {
                metaBits.append("Filters: \(filters.joined(separator: ", "))")
            }
            let metaAttrs: [NSAttributedString.Key: Any] = [
                .font: LegalBriefStyle.ListReport.metaFont,
                .foregroundColor: LegalBriefStyle.inkMuted
            ]
            (metaBits.joined(separator: " \u{2022} ") as NSString).draw(at: CGPoint(x: margin, y: cursor), withAttributes: metaAttrs)
            cursor += LegalBriefStyle.ListReport.metaFont.lineHeight + 8
            drawHorizontalRule(y: cursor, x1: margin, x2: pageW - margin,
                               color: LegalBriefStyle.ruleColor, width: 1)
            drawHorizontalRule(y: cursor + 2.2, x1: margin, x2: pageW - margin,
                               color: LegalBriefStyle.ruleColor, width: 0.4)
            cursor += 10
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: LegalBriefStyle.serif(10.5, weight: .regular, italic: true),
                .foregroundColor: LegalBriefStyle.inkSecondary
            ]
            ("\(title) \u{2014} \(subtitle) (continued)" as NSString).draw(at: CGPoint(x: margin, y: cursor), withAttributes: attrs)
            cursor += 16
            drawHorizontalRule(y: cursor, x1: margin, x2: pageW - margin, color: LegalBriefStyle.hairlineColor, width: 0.4)
            cursor += 8
        }

        drawFooter(page: page, leftLabel: "\(AppBranding.pdfMark) · \(AppBranding.pdfDomain)")
        return cursor
    }

    private static var listColumnGutter: CGFloat { PDFPageLayout.columnGutter }

    private static func listColWidths() -> (court: CGFloat, docket: CGFloat, parties: CGFloat, filed: CGFloat) {
        PDFPageLayout.listColumnWidths()
    }

    private enum ListRowMetrics {
        static let minPrimaryHeight: CGFloat = 14
        static let gapPrimaryToSubrow: CGFloat = 2
        static let gapLinkToSnippet: CGFloat = 2
        static let gapBeforeHairline: CGFloat = 4
        static let bandVerticalInset: CGFloat = 2
        static let bandHeightTrim: CGFloat = 4
    }

    private struct ListRowLayout {
        let primaryHeight: CGFloat
        let linkHeight: CGFloat
        let snippetHeight: CGFloat
        let totalHeight: CGFloat
        let margin: CGFloat
        let contentW: CGFloat
        let y: CGFloat

        func bandRect() -> CGRect {
            CGRect(
                x: margin - 4,
                y: y - ListRowMetrics.bandVerticalInset,
                width: contentW + 8,
                height: totalHeight - ListRowMetrics.bandHeightTrim
            )
        }

        var ruleY: CGFloat { y + totalHeight - ListRowMetrics.gapBeforeHairline }

        var linkBaselineY: CGFloat {
            y + primaryHeight + ListRowMetrics.gapPrimaryToSubrow
        }

        var snippetBaselineY: CGFloat {
            var offset = y + primaryHeight
            if linkHeight > 0 {
                offset += ListRowMetrics.gapPrimaryToSubrow + linkHeight + ListRowMetrics.gapLinkToSnippet
            } else {
                offset += ListRowMetrics.gapPrimaryToSubrow
            }
            return offset
        }
    }

    private static func listRowDateText(for row: SearchResultPDFModel) -> String {
        guard let d = row.filedDate else { return "" }
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: d)
    }

    private static func measureListRowLayout(
        row: SearchResultPDFModel,
        contentW: CGFloat,
        widths: (court: CGFloat, docket: CGFloat, parties: CGFloat, filed: CGFloat),
        margin: CGFloat,
        y: CGFloat
    ) -> ListRowLayout {
        let primaryHeight = max(
            LegalBriefStyle.ListReport.rowFont.lineHeight,
            LegalBriefStyle.ListReport.rowEmphasisFont.lineHeight,
            ListRowMetrics.minPrimaryHeight
        )
        let linkHeight: CGFloat = row.link == nil ? 0 : LegalBriefStyle.ListReport.linkFont.lineHeight
        let snippetHeight: CGFloat = row.summarySnippet?.truncatedSummary() == nil ? 0 : listSnippetFont.lineHeight

        var totalHeight = primaryHeight
        if linkHeight > 0 {
            totalHeight += ListRowMetrics.gapPrimaryToSubrow + linkHeight
        }
        if snippetHeight > 0 {
            totalHeight += (linkHeight > 0 ? ListRowMetrics.gapLinkToSnippet : ListRowMetrics.gapPrimaryToSubrow)
                + snippetHeight
        }
        totalHeight += ListRowMetrics.gapBeforeHairline

        return ListRowLayout(
            primaryHeight: primaryHeight,
            linkHeight: linkHeight,
            snippetHeight: snippetHeight,
            totalHeight: totalHeight,
            margin: margin,
            contentW: contentW,
            y: y
        )
    }

    private static func drawListColumnHeader(at y: CGFloat) -> CGFloat {
        let margin = PDFExporter.sharedListMargin
        let contentW = PDFPageLayout.contentWidth(margin: margin)
        let widths = listColWidths()
        var x = margin
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.ListReport.columnHeaderFont,
            .foregroundColor: LegalBriefStyle.inkSecondary,
            .kern: 0.8
        ]

        let cols: [(String, CGFloat)] = [
            ("COURT", widths.court),
            ("DOCKET NO.", widths.docket),
            ("PARTIES", widths.parties),
            ("FILED", widths.filed)
        ]
        for (label, w) in cols {
            (label as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: headerAttrs)
            x += w + listColumnGutter
        }
        let lineY = y + LegalBriefStyle.ListReport.columnHeaderFont.lineHeight + 2
        drawHorizontalRule(y: lineY, x1: margin, x2: margin + contentW, color: LegalBriefStyle.ruleColor, width: 0.6)
        return lineY + 4
    }

    private static func estimateListRowHeight(_ row: SearchResultPDFModel) -> CGFloat {
        let margin = PDFExporter.sharedListMargin
        let contentW = PDFPageLayout.contentWidth(margin: margin)
        let widths = listColWidths()
        return measureListRowLayout(row: row, contentW: contentW, widths: widths, margin: margin, y: 0).totalHeight
    }

    private static func drawListRow(_ row: SearchResultPDFModel, index: Int, startingAt y: CGFloat, context: UIGraphicsPDFRendererContext) {
        let margin = PDFExporter.sharedListMargin
        let pageW = PDFExporter.sharedPageSize.width
        let contentW = PDFPageLayout.contentWidth(margin: margin)
        let widths = listColWidths()
        let layout = measureListRowLayout(row: row, contentW: contentW, widths: widths, margin: margin, y: y)

        if !index.isMultiple(of: 2) {
            LegalBriefStyle.altRowFill.setFill()
            UIBezierPath(rect: layout.bandRect()).fill()
        }

        var x = margin
        let rowAttrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.ListReport.rowFont,
            .foregroundColor: LegalBriefStyle.inkPrimary
        ]
        let mutedAttrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.ListReport.rowFont,
            .foregroundColor: LegalBriefStyle.inkSecondary
        ]
        let emphAttrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.ListReport.rowEmphasisFont,
            .foregroundColor: LegalBriefStyle.inkPrimary
        ]
        let primaryH = layout.primaryHeight

        drawSingleLine(row.courtAbbrev, in: CGRect(x: x, y: y, width: widths.court, height: primaryH), attributes: mutedAttrs)
        x += widths.court + listColumnGutter

        drawSingleLine(row.docketNumber ?? "", in: CGRect(x: x, y: y, width: widths.docket, height: primaryH), attributes: rowAttrs)
        x += widths.docket + listColumnGutter

        drawSingleLine(row.parties, in: CGRect(x: x, y: y, width: widths.parties, height: primaryH), attributes: emphAttrs)
        x += widths.parties + listColumnGutter

        drawSingleLine(listRowDateText(for: row), in: CGRect(x: x, y: y, width: widths.filed, height: primaryH), attributes: mutedAttrs)

        if let link = row.link, layout.linkHeight > 0 {
            _ = drawHyperlinkedText(
                fittedLinkText(link, font: LegalBriefStyle.ListReport.linkFont, width: contentW),
                url: link,
                origin: CGPoint(x: margin, y: layout.linkBaselineY),
                width: contentW,
                font: LegalBriefStyle.ListReport.linkFont,
                context: context
            )
        }

        if let snippet = row.summarySnippet?.truncatedSummary(), layout.snippetHeight > 0 {
            let snippetAttrs: [NSAttributedString.Key: Any] = [
                .font: listSnippetFont,
                .foregroundColor: LegalBriefStyle.inkSecondary
            ]
            let prefix = row.keyword.map { "[\($0)]  " } ?? ""
            drawSingleLine(
                prefix + snippet,
                in: CGRect(x: margin, y: layout.snippetBaselineY, width: contentW, height: layout.snippetHeight),
                attributes: snippetAttrs
            )
        }

        drawHorizontalRule(
            y: layout.ruleY,
            x1: margin,
            x2: pageW - margin,
            color: LegalBriefStyle.hairlineColor,
            width: 0.3
        )
    }

    private static let listSnippetFont = LegalBriefStyle.serif(8.5, italic: true)

    private static func drawSingleLine(_ text: String, in rect: CGRect, attributes: [NSAttributedString.Key: Any]) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        var attrs = attributes
        attrs[.paragraphStyle] = para
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
    }

    private static func linkAttributes(font: UIFont, underline: Bool = true) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: LegalBriefStyle.linkInk
        ]
        if underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }

    private static func linkParagraphStyle() -> NSParagraphStyle {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byCharWrapping
        return para
    }

    private static func measureAttributedText(_ attributed: NSAttributedString, width: CGFloat) -> CGSize {
        let bounding = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil)
        return CGSize(width: ceil(bounding.width), height: ceil(bounding.height))
    }

    private static func estimateLinkTextHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        var attrs = linkAttributes(font: font)
        attrs[.paragraphStyle] = linkParagraphStyle()
        let attributed = NSAttributedString(string: text, attributes: attrs)
        return measureAttributedText(attributed, width: width).height
    }

    private static func estimateWrappedTextHeight(_ text: String,
                                                  font: UIFont,
                                                  width: CGFloat,
                                                  lineSpacing: CGFloat = 0,
                                                  italic: Bool = false) -> CGFloat {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: para
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        return measureAttributedText(attributed, width: width).height
    }

    @discardableResult
    private static func fittedLinkText(_ url: URL, font: UIFont, width: CGFloat) -> String {
        var text = url.absoluteString
        for prefix in ["https://", "http://", "www."] where text.lowercased().hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        let attrs = linkAttributes(font: font)
        func fits(_ candidate: String) -> Bool {
            (candidate as NSString).size(withAttributes: attrs).width <= width
        }
        guard !fits(text) else { return text }
        var head = String(text.prefix(text.count / 2))
        var tail = String(text.suffix(text.count - head.count))
        while !head.isEmpty, !tail.isEmpty, !fits(head + "\u{2026}" + tail) {
            if head.count >= tail.count { head.removeLast() } else { tail.removeFirst() }
        }
        return head + "\u{2026}" + tail
    }

    private static func drawHyperlinkedText(_ text: String,
                                            url: URL,
                                            origin: CGPoint,
                                            width: CGFloat,
                                            font: UIFont,
                                            context: UIGraphicsPDFRendererContext) -> CGFloat {
        var attrs = linkAttributes(font: font)
        attrs[.paragraphStyle] = linkParagraphStyle()
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let size = measureAttributedText(attributed, width: width)
        let rect = CGRect(x: origin.x, y: origin.y - 1, width: width, height: size.height)
        attributed.draw(in: rect)
        context.cgContext.setURL(url as CFURL, for: rect)
        return size.height
    }

    private static func drawHorizontalRule(y: CGFloat, x1: CGFloat, x2: CGFloat, color: UIColor, width: CGFloat) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.saveGState()
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(width)
        cg.move(to: CGPoint(x: x1, y: y))
        cg.addLine(to: CGPoint(x: x2, y: y))
        cg.strokePath()
        cg.restoreGState()
    }

    @discardableResult
    private static func drawCenteredText(_ text: String, font: UIFont, ink: UIColor, startingAt y: CGFloat,
                                         margin: CGFloat, contentWidth: CGFloat, lineSpacing: CGFloat = 0) -> CGFloat {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = lineSpacing
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ink,
            .paragraphStyle: para
        ]
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        let h = ceil(bounding.height)
        (text as NSString).draw(in: CGRect(x: margin, y: y, width: contentWidth, height: h), withAttributes: attrs)
        return y + h
    }

    private static func drawCenteredCaptionParties(plaintiff: String, defendant: String,
                                                   startingAt y: CGFloat,
                                                   margin: CGFloat,
                                                   contentWidth: CGFloat) -> CGFloat {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let plaintiffAttrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.SingleCase.captionPartyFont,
            .foregroundColor: LegalBriefStyle.inkPrimary,
            .paragraphStyle: para
        ]
        let vAttrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.SingleCase.captionVFont,
            .foregroundColor: LegalBriefStyle.inkPrimary,
            .paragraphStyle: para
        ]
        let defendantAttrs = plaintiffAttrs

        let combined = NSMutableAttributedString()
        combined.append(NSAttributedString(string: plaintiff, attributes: plaintiffAttrs))
        combined.append(NSAttributedString(string: "  v.  ", attributes: vAttrs))
        combined.append(NSAttributedString(string: defendant, attributes: defendantAttrs))

        let singleLineWidth = ceil(combined.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil).width)

        if singleLineWidth > contentWidth * 0.95 {
            var cursor = y
            cursor = drawCenteredText(plaintiff,
                                      font: LegalBriefStyle.SingleCase.captionPartyFont,
                                      ink: LegalBriefStyle.inkPrimary,
                                      startingAt: cursor, margin: margin, contentWidth: contentWidth)
            cursor = drawCenteredText("v.",
                                      font: LegalBriefStyle.SingleCase.captionVFont,
                                      ink: LegalBriefStyle.inkPrimary,
                                      startingAt: cursor, margin: margin, contentWidth: contentWidth)
            cursor = drawCenteredText(defendant,
                                      font: LegalBriefStyle.SingleCase.captionPartyFont,
                                      ink: LegalBriefStyle.inkPrimary,
                                      startingAt: cursor, margin: margin, contentWidth: contentWidth)
            return cursor
        }

        let bounding = combined.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let h = ceil(bounding.height)
        combined.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: h))
        return y + h
    }

    static func drawFooter(page: Int, leftLabel: String) {
        let margin = PDFExporter.sharedBriefMargin
        let pageW = PDFExporter.sharedPageSize.width
        let pageH = PDFExporter.sharedPageSize.height
        let baseY = pageH - 36
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.SingleCase.footerFont,
            .foregroundColor: LegalBriefStyle.inkSecondary
        ]
        let emphAttrs: [NSAttributedString.Key: Any] = [
            .font: LegalBriefStyle.SingleCase.footerEmphasis,
            .foregroundColor: LegalBriefStyle.inkPrimary
        ]

        drawHorizontalRule(y: baseY - 8, x1: margin, x2: pageW - margin,
                           color: LegalBriefStyle.hairlineColor, width: 0.4)

        (leftLabel as NSString).draw(at: CGPoint(x: margin, y: baseY), withAttributes: emphAttrs)
        let dateStr = AppBranding.pdfPreparedLine()
        let rightSize = (dateStr as NSString).size(withAttributes: footerAttrs)
        (dateStr as NSString).draw(at: CGPoint(x: pageW - margin - rightSize.width, y: baseY), withAttributes: footerAttrs)

        let placeholder = "Page \(page)"
        let pSize = (placeholder as NSString).size(withAttributes: footerAttrs)
        (placeholder as NSString).draw(at: CGPoint(x: (pageW - pSize.width) / 2, y: baseY), withAttributes: footerAttrs)
    }
}

enum PDFTextUtilities {

    static func parsePartiesCaption(_ title: String) -> (plaintiff: String, defendant: String)? {
        let patterns = [
            #"^(.{2,140}?)\s+v\.\s+(.{2,140}?)$"#,
            #"^(.{2,140}?)\s+vs\.\s+(.{2,140}?)$"#,
            #"^(.{2,140}?)\s+vs?\s+(.{2,140}?)$"#
        ]
        let cleaned = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
                  match.numberOfRanges == 3,
                  let pRange = Range(match.range(at: 1), in: cleaned),
                  let dRange = Range(match.range(at: 2), in: cleaned)
            else { continue }
            let plaintiff = String(cleaned[pRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let defendant = String(cleaned[dRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if plaintiff.isEmpty || defendant.isEmpty { continue }
            return (plaintiff, defendant)
        }
        return nil
    }

    static func courtAbbreviation(courtId: String, fullName: String) -> String {
        let lower = fullName.lowercased()
        if lower.contains("court of appeals"), let circuit = circuitFromName(fullName) {
            return circuit
        }
        if lower.contains("supreme court") { return "U.S." }
        if let district = shortCourtDistrict(fullName: fullName) ?? shortStateCourt(fullName: fullName) {
            return lower.contains("bankruptcy") ? "\(district) Bankr." : district
        }
        if let feed = shortFeedCourt(courtId: courtId) { return feed }
        return fullName
    }

    private static func shortStateCourt(fullName: String) -> String? {
        let pattern = #"^(.+?)\s+(?:(Northern|Southern|Eastern|Western|Central|Middle)\s+)?(?:Bankruptcy|District)\s+Court"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: fullName, range: NSRange(fullName.startIndex..., in: fullName)),
              let stateRange = Range(m.range(at: 1), in: fullName),
              let state = knownStateAbbrev(String(fullName[stateRange])) else { return nil }
        let direction = Range(m.range(at: 2), in: fullName).map { String(fullName[$0].prefix(1)).uppercased() + ".D." }
        return "\(direction ?? "D.") \(state)"
    }

    private static func shortFeedCourt(courtId: String) -> String? {
        var code = (courtId.lowercased().split(separator: "-").last).map(String.init) ?? ""
        guard code.count >= 3, let stateName = StateAbbreviations.name(for: String(code.prefix(2))),
              let state = knownStateAbbrev(stateName) else { return nil }
        code.removeFirst(2)
        let bankruptcy = code.hasSuffix("b")
        if bankruptcy { code.removeLast() }
        let regions = ["n": "N.D.", "s": "S.D.", "e": "E.D.", "w": "W.D.", "c": "C.D.", "m": "M.D."]
        let region: String
        switch code {
        case "", "d": region = "D."
        case let value where value.count <= 2 && regions[String(value.prefix(1))] != nil: region = regions[String(value.prefix(1))]!
        default: return nil
        }
        return bankruptcy ? "\(region) \(state) Bankr." : "\(region) \(state)"
    }

    private static func shortCourtDistrict(fullName: String) -> String? {
        let pattern = #"(Northern|Southern|Eastern|Western|Central|Middle|District)\s+District\s+of\s+([A-Za-z .'\-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: fullName, range: NSRange(fullName.startIndex..., in: fullName)),
              m.numberOfRanges == 3,
              let dirRange = Range(m.range(at: 1), in: fullName),
              let stateRange = Range(m.range(at: 2), in: fullName)
        else {
            if fullName.lowercased().contains("district of columbia") { return "D.D.C." }
            return nil
        }
        let dir = String(fullName[dirRange]).lowercased()
        let prefix: String
        switch dir {
        case "northern": prefix = "N.D."
        case "southern": prefix = "S.D."
        case "eastern":  prefix = "E.D."
        case "western":  prefix = "W.D."
        case "central":  prefix = "C.D."
        case "middle":   prefix = "M.D."
        case "district": prefix = "D."
        default: prefix = "D."
        }
        let state = String(fullName[stateRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix) \(stateAbbrev(state))"
    }

    private static func stateAbbrev(_ state: String) -> String {
        knownStateAbbrev(state) ?? state.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func knownStateAbbrev(_ state: String) -> String? {
        let map: [String: String] = [
            "Alabama": "Ala.", "Alaska": "Alaska", "Arizona": "Ariz.", "Arkansas": "Ark.",
            "California": "Cal.", "Colorado": "Colo.", "Connecticut": "Conn.", "Delaware": "Del.",
            "Florida": "Fla.", "Georgia": "Ga.", "Hawaii": "Haw.", "Idaho": "Idaho",
            "Illinois": "Ill.", "Indiana": "Ind.", "Iowa": "Iowa", "Kansas": "Kan.",
            "Kentucky": "Ky.", "Louisiana": "La.", "Maine": "Me.", "Maryland": "Md.",
            "Massachusetts": "Mass.", "Michigan": "Mich.", "Minnesota": "Minn.",
            "Mississippi": "Miss.", "Missouri": "Mo.", "Montana": "Mont.", "Nebraska": "Neb.",
            "Nevada": "Nev.", "New Hampshire": "N.H.", "New Jersey": "N.J.", "New Mexico": "N.M.",
            "New York": "N.Y.", "North Carolina": "N.C.", "North Dakota": "N.D.", "Ohio": "Ohio",
            "Oklahoma": "Okla.", "Oregon": "Ore.", "Pennsylvania": "Pa.", "Rhode Island": "R.I.",
            "South Carolina": "S.C.", "South Dakota": "S.D.", "Tennessee": "Tenn.", "Texas": "Tex.",
            "Utah": "Utah", "Vermont": "Vt.", "Virginia": "Va.", "Washington": "Wash.",
            "West Virginia": "W. Va.", "Wisconsin": "Wis.", "Wyoming": "Wyo.",
            "Puerto Rico": "P.R.", "Guam": "Guam", "Virgin Islands": "V.I."
        ]
        return map[state.trimmingCharacters(in: .whitespacesAndNewlines).capitalized]
    }

    private static func circuitFromName(_ name: String) -> String? {
        let pattern = #"(First|Second|Third|Fourth|Fifth|Sixth|Seventh|Eighth|Ninth|Tenth|Eleventh|Federal|D\.?C\.?)\s+Circuit"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(m.range(at: 1), in: name)
        else { return nil }
        let circuit = String(name[range])
        let map: [String: String] = [
            "first": "1st Cir.", "second": "2d Cir.", "third": "3d Cir.",
            "fourth": "4th Cir.", "fifth": "5th Cir.", "sixth": "6th Cir.",
            "seventh": "7th Cir.", "eighth": "8th Cir.", "ninth": "9th Cir.",
            "tenth": "10th Cir.", "eleventh": "11th Cir.",
            "federal": "Fed. Cir.", "dc": "D.C. Cir.", "d.c.": "D.C. Cir.", "d.c": "D.C. Cir."
        ]
        return map[circuit.lowercased()] ?? "\(circuit) Cir."
    }

    static func expandCourtName(_ name: String) -> String {
        if name.lowercased().contains("united states") { return name }
        if name.lowercased().contains("court") { return name }
        return name
    }

    static func derivePACERURL(from entry: CaseEntry, validatedDocket: URL?) -> URL? {
        guard let docket = validatedDocket,
              let host = docket.host,
              URLValidator.isCourtDomain(host) else {
            return nil
        }
        let normalized = host.lowercased()
        let isPacerOrCourtDocket = normalized == "pacer.gov"
            || normalized.hasSuffix(".pacer.gov")
            || normalized == "uscourts.gov"
            || normalized.hasSuffix(".uscourts.gov")
        return isPacerOrCourtDocket ? docket : nil
    }
}

private extension String {
    func truncatedSummary(maxChars: Int = 240) -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.count <= maxChars { return trimmed }
        let endIndex = index(startIndex, offsetBy: maxChars)
        return "\(trimmed[..<endIndex])\u{2026}"
    }
}
