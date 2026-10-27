import SwiftUI

extension CaseDisplayable {
    var displayCourtName: String {
        let entryTitle = (self as? CaseEntry)?.displayTitle ?? title
        let rawExplicit = (self as? CaseEntry)?.courtName ?? (self as? CaseMatch)?.courtName
        let explicit = rawExplicit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedExplicit = explicit.flatMap { name in
            name.isEmpty || name.caseInsensitiveCompare(entryTitle) == .orderedSame ? nil : name
        }
        return resolveCourtName(courtId: courtId, explicitName: resolvedExplicit)
    }

    var displayRowTitle: String {
        if let entry = self as? CaseEntry { return entry.displayTitle }
        return title.removingLeadingCaseIdentifier()
    }
}

struct CaseRow<Item: CaseDisplayable>: View {
    let item: Item
    var isUnread = false
    var isStarred = false
    var badge: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isUnread ? Color.caserAccent : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayRowTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                if let date = item.pubDate {
                    Text(date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize()
                }
                HStack(spacing: 4) {
                    if isStarred {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.caserAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.caserAccent.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var subtitle: String {
        [item.displayCourtName, item.displayCaseNumber].compactMap { $0 }.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var parts = [item.displayRowTitle, item.displayCourtName]
        if let number = item.displayCaseNumber { parts.append("Case \(number)") }
        if let date = item.pubDate { parts.append("Filed \(date.formatted(date: .abbreviated, time: .omitted))") }
        if isUnread { parts.append("Unread") }
        if isStarred { parts.append("Starred") }
        if let badge { parts.append(badge) }
        return parts.joined(separator: ", ")
    }
}

extension View {
    func caserListRow() -> some View {
        listRowBackground(Color.white.opacity(0.05))
            .listRowSeparatorTint(.white.opacity(0.1))
    }

    func caserListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { MainBackground() }
    }
}

struct CaserSectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let trailing {
                Text(trailing)
                    .monospacedDigit()
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white.opacity(0.6))
        .textCase(nil)
    }
}
