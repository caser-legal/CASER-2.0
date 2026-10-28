import SwiftUI
import UIKit

struct CaseDetailView: View {
    let entry: CaseEntry
    var matchedKeyword: String?
    @Environment(\.dismiss) var dismiss
    @Environment(SavedCasesManager.self) private var savedManager
    @State private var atticus: CaseInsightsModel
    @State private var isSaved = false
    @State private var showAllParties = false
    @State private var exportURL: URL?
    @State private var exportFailed = false
    @State private var pdfPreviewItem: PDFPreviewItem?
    @State private var isPreparingExport = false
    @State private var isMonitoringTerm = false
    @State private var isCreatingAlert = false
    @State private var alertFeedback: String?
    @State private var exportErrorMessage: String?

    init(entry: CaseEntry, matchedKeyword: String? = nil) {
        self.entry = entry
        self.matchedKeyword = matchedKeyword
        _atticus = State(initialValue: CaseInsightsModel(entry: entry))
    }

    var courtName: String {
        resolveCourtName(courtId: entry.courtId, explicitName: entry.courtName)
    }

    var displayTitle: String { entry.displayTitle }

    var summaryText: String {
        entry.cleanedSummary
    }

    var summaryDisplayText: String {
        var text = summaryText
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: #"\s*\(\d+\)$"#, options: .regularExpression) {
            text = String(text[..<range.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var validatedDocketURL: String? {
        guard let raw = entry.link.trimmedNonEmpty,
              URLValidator.safeCourtURL(raw) != nil else { return nil }
        return raw
    }

    var primaryDocumentAction: (title: String, icon: String, url: String)? {
        let docketURL = validatedDocketURL?.lowercased()
        guard let raw = entry.primaryDocumentURL?.trimmedNonEmpty,
              URLValidator.safeCourtURL(raw) != nil else { return nil }
        if let docketURL, raw.lowercased() == docketURL {
            return nil
        }
        let label = entry.primaryDocumentIsZip ? "Download ZIP" : "View Document"
        let icon = entry.primaryDocumentIsZip ? "doc.zipper" : "arrow.down.doc.fill"
        return (label, icon, raw)
    }

    var additionalDocumentLinks: [(title: String, icon: String, url: String)] {
        var links: [(String, String, String)] = []
        let primary = primaryDocumentAction?.url.lowercased()

        if let pdf = entry.govinfoPdfUrl?.trimmedNonEmpty,
           URLValidator.safeCourtURL(pdf) != nil,
           pdf.lowercased() != primary {
            links.append(("GovInfo PDF", "doc.text.fill", pdf))
        }
        if let zip = entry.govinfoZipUrl?.trimmedNonEmpty,
           URLValidator.safeCourtURL(zip) != nil,
           zip.lowercased() != primary {
            links.append(("Download ZIP Archive", "archivebox", zip))
        }
        if let html = entry.govinfoHtmlUrl?.trimmedNonEmpty,
           URLValidator.safeCourtURL(html) != nil {
            links.append(("View on GovInfo", "safari", html))
        }

        return links
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayTitle)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = displayTitle
                                } label: {
                                    Label("Copy Title", systemImage: "doc.on.doc")
                                }
                            }
                        
                        CaseCardMetadataHeader(
                            courtName: courtName,
                            date: entry.pubDate
                        )

                        if let matched = matchedKeyword?.trimmingCharacters(in: .whitespacesAndNewlines), !matched.isEmpty {
                            Text("Matched: \(matched)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.1), in: Capsule())
                        }

                        if let caseNumber = entry.displayCaseNumber {
                            Label(caseNumber, systemImage: "number.square")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        if let citation = entry.displayCitation {
                            Label(citation, systemImage: "text.book.closed")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                    }
                    
                    if atticus.hasConsent {
                        AskAtticusBar(model: atticus)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    }

                    CaseInsightsSection(model: atticus)

                    let parties = entry.parties
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if !parties.isEmpty {
                        DetailSection(title: "Parties") {
                            ForEach(Array((showAllParties ? parties : Array(parties.prefix(2))).enumerated()), id: \.offset) { index, party in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Party \(index + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                    Text(cleanPartyName(party, isFirst: false))
                                        .font(.body)
                                        .foregroundStyle(.white)
                                }
                                .padding(.vertical, 4)
                            }
                            
                            if parties.count > 2 {
                                Button(showAllParties ? "Show Fewer Parties" : "Show All \(parties.count) Parties") {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showAllParties.toggle()
                                    }
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.blue)
                                .frame(minHeight: 44, alignment: .leading)
                                .accessibilityHint(showAllParties ? "Collapses the party list" : "Shows every party listed in this filing")
                            }
                        }
                    }
                    
                    let summaryIsPlaceholder = summaryText == CaseEntry.summaryPlaceholder
                    if !summaryText.isEmpty && !summaryIsPlaceholder {
                        DetailSection(title: "Summary") {
                            Text(summaryDisplayText)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = summaryText
                                    } label: {
                                        Label("Copy Description", systemImage: "doc.on.doc")
                                    }
                                }
                        }
                    }
                    
                    DetailSection(title: "Case Details") {
                        DetailInfoRow(label: "Court", value: courtName)
                        if let caseNumber = entry.displayCaseNumber {
                            DetailInfoRow(label: "Case Number", value: caseNumber)
                        }
                        if let citation = entry.displayCitation {
                            DetailInfoRow(label: "Citation", value: citation)
                        }
                        if let filed = entry.pubDate?.filingDisplayString() {
                            DetailInfoRow(label: "Filed", value: filed)
                        }
                        if let state = (entry.modsCourtState?.trimmedNonEmpty ?? entry.state?.trimmedNonEmpty) {
                            DetailInfoRow(label: "State", value: state)
                        }
                        if let type = (entry.modsCourtType?.trimmedNonEmpty ?? entry.caseType?.trimmedNonEmpty) {
                            DetailInfoRow(label: "Case Type", value: type.capitalized)
                        }
                        if let timezone = entry.timezone?.trimmedNonEmpty {
                            DetailInfoRow(label: "Timezone", value: timezone)
                        }
                        if let source = entry.source?.trimmedNonEmpty {
                            DetailInfoRow(label: "Source", value: source.capitalized)
                        }
                        DetailInfoRow(label: "Feed ID", value: "CASER")
                    }

                    if !entry.displaySubjects.isEmpty {
                        DetailSection(title: "Subjects") {
                            ForEach(entry.displaySubjects, id: \.self) { subject in
                                Text("• \(subject)")
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }

                    if !entry.displayCategories.isEmpty {
                        DetailSection(title: "Categories") {
                            ForEach(entry.displayCategories, id: \.self) { category in
                                Text("• \(category)")
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }

                    CaseFollowUpSection(model: atticus)

                    VStack(spacing: 12) {
                        Button {
                            Task { await toggleAlertFromDetail() }
                        } label: {
                            HStack {
                                if isCreatingAlert {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(isMonitoringTerm ? Color.caserAccent : .white)
                                } else {
                                    Image(systemName: isMonitoringTerm ? "bell.fill" : "bell.badge")
                                }
                                Text(alertButtonTitle)
                                Spacer()
                            }
                            .font(.body.weight(.medium))
                            .foregroundStyle(isMonitoringTerm ? Color.caserAccent : .white)
                            .padding(16)
                            .background(
                                (isMonitoringTerm ? Color.caserAccent.opacity(0.18) : .white.opacity(0.08)),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isCreatingAlert)
                        .allowsHitTesting(!isCreatingAlert)
                        .accessibilityLabel(
                            isMonitoringTerm
                                ? "Alert on for this case, double tap to turn off"
                                : "Add alert for this case"
                        )

                        if let alertFeedback {
                            Text(alertFeedback)
                                .font(.caption)
                                .foregroundStyle(Color.caserAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.caserAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        }

                        if let docketURL = validatedDocketURL {
                            LinkButton(title: "View Docket", url: docketURL, icon: "doc.text.fill")
                        }
                        
                        Button {
                            Task { await openPDFPreview() }
                        } label: {
                            exportPDFLabel
                        }
                        .disabled(isPreparingExport)
                        .accessibilityLabel(exportFailed ? "Retry PDF export" : "Export PDF")

                        if let action = primaryDocumentAction {
                            LinkButton(title: action.title, url: action.url, icon: action.icon)
                        }

                        ForEach(additionalDocumentLinks, id: \.url) { link in
                            LinkButton(title: link.title, url: link.url, icon: link.icon)
                        }
                    }

                }
                .padding(20)
                .containerRelativeFrame(.horizontal, alignment: .leading)
            }
            .background {
                MainBackground()
            }
            .navigationTitle("Case Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await toggleSave()
                        }
                    } label: {
                        Image(systemName: isSaved ? "heart.fill" : "heart")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel(isSaved ? "Remove from saved cases" : "Save case")
                }
            }
            .task {
                await savedManager.loadSaved()
                isSaved = savedManager.isSaved(entry.id)
            }
            .task(id: entry.id) {
                await refreshMonitoringState()
            }
            .task(id: atticus.hasConsent) {
                await atticus.load()
            }
            .pdfPreviewSheet(item: $pdfPreviewItem)
            .onChange(of: alertFeedback) { _, message in
                guard UIAccessibility.isVoiceOverRunning, let message else { return }
                UIAccessibility.post(notification: .announcement, argument: message)
            }
            .alert("PDF Export Unavailable", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { exportErrorMessage = nil }
            } message: {
                if let exportErrorMessage {
                    Text(exportErrorMessage)
                }
            }
        }
    }

    private var alertButtonTitle: String {
        if isCreatingAlert {
            return isMonitoringTerm ? "Turning Off Alert…" : "Adding Alert…"
        }
        return isMonitoringTerm ? "Alert On" : "Add Alert"
    }

    private func refreshMonitoringState() async {
        isMonitoringTerm = AlertCreationService.shared.isCaseAlertOn(for: entry)
    }

    private func toggleAlertFromDetail() async {
        guard !isCreatingAlert else { return }

        let service = AlertCreationService.shared
        let term = service.caseNumberTerm(for: entry)

        isCreatingAlert = true
        defer { isCreatingAlert = false }

        do {
            let result = try await service.toggleAlertForCase(entry: entry)
            withAnimation(.easeInOut(duration: 0.2)) {
                isMonitoringTerm = service.isCaseAlertOn(for: entry)
            }
            switch result {
            case .created:
                alertFeedback = "Alert added for case \(term). You will be notified when new filings appear for this docket."
            case .enabled:
                alertFeedback = "Alert turned on for case \(term). You will be notified when new filings appear for this docket."
            case .disabled:
                alertFeedback = "Alert turned off for case \(term). You will not receive notifications until you turn it back on."
            }
            scheduleAlertFeedbackDismissal()
        } catch {
            alertFeedback = error.localizedDescription
            scheduleAlertFeedbackDismissal()
        }
    }

    private func scheduleAlertFeedbackDismissal() {
        Task {
            try? await Task.sleep(for: .seconds(4))
            alertFeedback = nil
        }
    }
    
    private func cleanPartyName(_ name: String, isFirst: Bool) -> String {
        guard isFirst else { return name }
        return name.replacingOccurrences(of: "^[\\d:]+[-\\w]+\\s*", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    
    private var exportPDFLabel: some View {
        HStack {
            if isPreparingExport {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "doc.richtext")
            }
            Text(exportFailed ? "Retry Export PDF" : (isPreparingExport ? "Preparing…" : "Export PDF"))
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption)
        }
        .font(.body.weight(.medium))
        .foregroundStyle(.white)
        .padding(16)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @MainActor
    private func openPDFPreview() async {
        isPreparingExport = true
        defer { isPreparingExport = false }

        if let exportURL, !FileManager.default.fileExists(atPath: exportURL.path) {
            self.exportURL = nil
        }

        if exportURL == nil {
            if let url = await PDFExporter.exportSingleCase(entry) {
                exportURL = url
                exportFailed = false
                exportErrorMessage = nil
            } else {
                exportFailed = true
                exportErrorMessage = "CASER could not create this PDF. You can try again now."
                return
            }
        }

        if let exportURL {
            pdfPreviewItem = PDFPreviewItem(url: exportURL, title: displayTitle)
        }
    }
    
    @MainActor
    private func toggleSave() async {
        if isSaved {
            await savedManager.unsave(entry.id)
            isSaved = false
        } else {
            let success = await savedManager.save(entry)
            if success {
                isSaved = true
            }
        }
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct DetailInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                labelText
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 16)
                valueText
                    .fixedSize(horizontal: true, vertical: false)
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                labelText
                valueText
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
    }

    private var valueText: some View {
        Text(value)
            .font(.body)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LinkButton: View {
    let title: String
    let url: String
    let icon: String
    
    var body: some View {
        Button {
            if let url = URLValidator.safeURL(url) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(16)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
