import SwiftUI
import UIKit

struct CaseDetailPresentation: Identifiable {
    let id: String
    let entry: CaseEntry
    let matchedKeyword: String?
}

protocol CaseDisplayable: Identifiable, Sendable {
    var id: String { get }
    var title: String { get }
    var courtId: String { get }
    var description: String { get }
    var primaryDocumentURL: String? { get }
    var pubDate: Date? { get }
    var matchedKeyword: String? { get }
    var displayCaseNumber: String? { get }
    var displayCitation: String? { get }
    var docketURL: String? { get }

    var caseEntryForDetail: CaseEntry { get }
}

extension CaseEntry {
    var caseEntryForDetail: CaseEntry { self }
}

extension CaseMatch {
    var caseEntryForDetail: CaseEntry { asCaseEntry() }
}

struct CaseCardMetadataHeader: View {
    let courtName: String
    let date: Date?
    var starred = false
    var read = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "building.columns")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(courtName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(.white.opacity(0.62))
            .frame(maxWidth: .infinity, alignment: .leading)

            if starred {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Starred")
            }
            if read {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Read")
            }

            if let date {
                Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(alignment: .trailing)
            }
        }
    }
}



struct UnifiedCaseCard<T: CaseDisplayable>: View {
    let item: T
    var manager: SavedCasesManager?
    var onOpenDetail: ((CaseDetailPresentation) -> Void)?
    var onDelete: (() -> Void)?
    var onToggleRead: (() -> Void)?
    var onToggleStarred: (() -> Void)?
    
    @State private var localDetailPresentation: CaseDetailPresentation?
    @State private var isMonitoringTerm = false
    @State private var isCreatingAlert = false
    @State private var alertFeedback: String?

    private var isSaved: Bool {
        manager?.isSaved(savedCaseID) ?? false
    }

    private var savedCaseID: String { item.caseEntryForDetail.id }

    private var caseEntry: CaseEntry? {
        item as? CaseEntry
    }

    private var caseMatch: CaseMatch? {
        item as? CaseMatch
    }

    private var accessibilitySummary: String {
        var parts = [resolvedTitle, courtName]
        if let caseNumber = item.displayCaseNumber {
            parts.append("Case number \(caseNumber)")
        }
        if let citation = item.displayCitation {
            parts.append("Citation \(citation)")
        }
        if let date = item.pubDate {
            parts.append("Filed \(date.filingDisplayString())")
        }
        if let keyword = item.matchedKeyword?.trimmingCharacters(in: .whitespacesAndNewlines), !keyword.isEmpty {
            parts.append("Matched keyword \(keyword)")
        }
        if let match = caseMatch {
            if match.starred { parts.append("Starred") }
            parts.append(match.read ? "Read" : "Unread")
        }

        let descriptionSource = caseEntry?.cleanedDescription ?? item.description
        let snippet = descriptionSource.sanitizedSnippetText()
        if !snippet.isEmpty {
            parts.append("Summary \(String(snippet.prefix(180)))")
        }
        return parts.joined(separator: ". ")
    }
    
    var courtName: String { item.displayCourtName }

    private var resolvedTitle: String { item.displayRowTitle }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                openDetail()
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    cardHeaderSection
                        .padding(.trailing, manager == nil ? 0 : 44)
                    cardTitleSection
                    cardMetadataSection
                    cardDescriptionSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint("Opens case details")

            cardActionButtons

            if let alertFeedback {
                Text(alertFeedback)
                    .font(.caption2)
                    .foregroundStyle(Color.caserAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if manager != nil {
                Button {
                    Task { await toggleSave() }
                } label: {
                    Image(systemName: isSaved ? "heart.fill" : "heart")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(isSaved ? "Unsave case" : "Save case")
                .buttonStyle(.plain)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .contextMenu {
            if let match = caseMatch {
                Button {
                    onToggleRead?()
                } label: {
                    Label(match.read ? "Mark as Unread" : "Mark as Read", systemImage: match.read ? "envelope.badge" : "envelope.open")
                }
                
                Button {
                    onToggleStarred?()
                } label: {
                    Label(match.starred ? "Unstar" : "Star", systemImage: match.starred ? "star.slash" : "star")
                }
                
                Divider()
            }
            
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else if let manager, isSaved {
                Button(role: .destructive) {
                    Task {
                        await manager.unsave(savedCaseID)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .sheet(item: $localDetailPresentation) { presentation in
            CaseDetailView(
                entry: presentation.entry,
                matchedKeyword: presentation.matchedKeyword
            )
        }
        .task(id: item.id) {
            await refreshMonitoringState()
        }
        .onChange(of: alertFeedback) { _, message in
            guard UIAccessibility.isVoiceOverRunning, let message else { return }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func openDetail() {
        let presentation = CaseDetailPresentation(
            id: item.id,
            entry: item.caseEntryForDetail,
            matchedKeyword: item.matchedKeyword
        )
        if let onOpenDetail {
            onOpenDetail(presentation)
        } else {
            localDetailPresentation = presentation
        }
    }

    private var cardHeaderSection: some View {
        CaseCardMetadataHeader(
            courtName: courtName,
            date: item.pubDate,
            starred: caseMatch?.starred ?? false,
            read: caseMatch?.read ?? false
        )
    }

    private var cardTitleSection: some View {
        Text(resolvedTitle)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = resolvedTitle
                } label: {
                    Label("Copy Title", systemImage: "doc.on.doc")
                }
            }
    }

    @ViewBuilder
    private var cardMetadataSection: some View {
        if let caseNumber = item.displayCaseNumber {
            Label {
                Text(caseNumber)
            } icon: {
                Image(systemName: "number.square")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
        }

        if let citation = item.displayCitation {
            Label {
                Text(citation)
            } icon: {
                Image(systemName: "text.book.closed")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var cardDescriptionSection: some View {
        let descriptionSource: String = {
            if let entry = item as? CaseEntry {
                return entry.cleanedDescription
            }
            return item.description
        }()
        let snippet = descriptionSource.sanitizedSnippetText()
        if !snippet.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "doc.text.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = snippet
                        } label: {
                            Label("Copy Description", systemImage: "doc.on.doc")
                        }
                    }
            }
        }
    }

    private var alertButtonTitle: String {
        if isCreatingAlert {
            return isMonitoringTerm ? "Turning Off…" : "Adding…"
        }
        return isMonitoringTerm ? "Alert On" : "Add Alert"
    }

    @ViewBuilder
    private var cardActionButtons: some View {
        HStack(spacing: 6) {
            Button {
                openDetail()
            } label: {
                compactActionLabel(
                    title: "Details",
                    systemImage: "info.circle",
                    foreground: .white.opacity(0.82),
                    background: .white.opacity(0.10)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44)

            if caseEntry != nil {
                Button {
                    Task { await createAlertFromCard() }
                } label: {
                    HStack(spacing: 4) {
                        if isCreatingAlert {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(isMonitoringTerm ? Color.caserAccent : .white)
                        } else {
                            Image(systemName: isMonitoringTerm ? "bell.fill" : "bell.badge")
                                .font(.caption2)
                        }
                        Text(isCreatingAlert ? alertButtonTitle : (isMonitoringTerm ? "Alert On" : "Alert"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isMonitoringTerm ? Color.caserAccent : .white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        isMonitoringTerm ? Color.caserAccent.opacity(0.16) : .white.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isCreatingAlert)
                .accessibilityLabel(
                    isMonitoringTerm
                        ? "Turn off alert for this case"
                        : "Add alert for this case"
                )
            }
        }
    }

    private func compactActionLabel(
        title: String,
        systemImage: String,
        foreground: Color,
        background: Color
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
    }

    private func refreshMonitoringState() async {
        guard let entry = caseEntry else {
            isMonitoringTerm = false
            return
        }
        isMonitoringTerm = AlertCreationService.shared.isCaseAlertOn(for: entry)
    }

    private func createAlertFromCard() async {
        guard let entry = caseEntry else { return }
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

    private func toggleSave() async {
        guard let manager else { return }

        if isSaved {
            await manager.unsave(savedCaseID)
        } else {
            _ = await manager.save(item.caseEntryForDetail)
        }
    }
}
