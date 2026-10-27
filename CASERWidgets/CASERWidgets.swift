import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CASERWidgets: WidgetBundle {
    var body: some Widget { CaserAlertLiveActivity() }
}

private enum Palette {
    static let accent = Color(red: 0.831, green: 0.627, blue: 0.090)
    static let newFiling = Color.green
    static let warning = Color.orange
}

private typealias AlertContext = ActivityViewContext<CaserAlertAttributes>

private struct StatusIcon: View {
    let state: CaserAlertAttributes.ContentState

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        if state.isSearching { return "magnifyingglass" }
        return state.hasNewFiling ? "bell.badge.fill" : "bell.fill"
    }

    private var color: Color {
        if state.isSearching { return Palette.accent }
        return state.hasNewFiling ? Palette.newFiling : Palette.accent
    }

    private var label: String {
        if state.isSearching { return "Searching" }
        return state.hasNewFiling ? "New filing" : "No new filings"
    }
}

private struct SearchNowButton: View {
    let keywordId: String
    let term: String
    let isSearching: Bool
    var compact = false

    var body: some View {
        Button(intent: SearchAlertNowIntent(keywordId: keywordId)) {
            Label(isSearching ? "Searching" : "Search", systemImage: isSearching ? "hourglass" : "arrow.clockwise")
                .labelStyle(.titleAndIcon)
                .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 6 : 7)
                .foregroundStyle(isSearching ? Color.secondary : Color.black)
                .background(isSearching ? Color.white.opacity(0.15) : Palette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSearching)
        .accessibilityLabel(isSearching ? "Searching courts for \(term)" : "Search courts now for \(term)")
    }
}

private struct SearchResultFigure: View {
    let search: CaserAlertAttributes.LastSearch

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(search.matchingFilings, format: .number)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(search.matchingFilings > 0 ? Palette.newFiling : .primary)
                Text("/")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(search.filingsSearched, format: .number)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            Text("matches / filings searched")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(search.matchingFilings) matches in \(search.filingsSearched) filings searched")
    }
}

private struct NewFilingsFigure: View {
    let state: CaserAlertAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(state.newFilingCount, format: .number)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(state.hasNewFiling ? Palette.newFiling : .primary)
            Text(state.newFilingCount == 1 ? "new filing since set" : "new filings since set")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.newFilingCount) new filings since the alert was set")
    }
}

private struct SearchProgressRow: View {
    let active: CaserAlertAttributes.ActiveSearch

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Searching \(active.courtsSearched) of \(active.courtsTotal) courts")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(active.startedAt, style: .timer)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 44, alignment: .trailing)
            }
            ProgressView(value: active.fractionComplete)
                .tint(Palette.accent)
            Text("\(active.filingsSearched.formatted()) filings read so far")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LatestFilingRow: View {
    let state: CaserAlertAttributes.ContentState

    var body: some View {
        if let title = state.latestFilingTitle {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .foregroundStyle(Palette.newFiling)
                    .accessibilityHidden(true)
                Text(title)
                    .lineLimit(1)
                if let court = state.latestFilingCourt {
                    Text("· \(court)")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .layoutPriority(-1)
                }
            }
            .font(.caption)
        }
    }
}

private struct FooterRow: View {
    let context: AlertContext

    var body: some View {
        let state = context.state
        HStack(spacing: 4) {
            if context.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
                    .accessibilityHidden(true)
                Text(state.isSearching ? "Search was interrupted. Tap Search to try again." : "Checks are overdue. Open CASER or tap Search.")
                    .foregroundStyle(Palette.warning)
                    .lineLimit(1)
            } else if let finished = state.lastSearch?.finishedAt ?? state.lastCheckedAt {
                Text("Searched ") + Text(finished, style: .relative) + Text(" ago")
                if let search = state.lastSearch, search.courtsSearched > 0 {
                    Text("· \(search.courtsSearched) courts")
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("Next ") + Text(state.nextCheckAt, style: .time)
            } else {
                Text("Waiting for the first search")
                Spacer(minLength: 4)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct LockScreenView: View {
    let context: AlertContext

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                StatusIcon(state: state)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.attributes.term)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                SearchNowButton(
                    keywordId: context.attributes.keywordId,
                    term: context.attributes.term,
                    isSearching: state.isSearching && !context.isStale
                )
            }

            if let active = state.activeSearch, !context.isStale {
                SearchProgressRow(active: active)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    NewFilingsFigure(state: state)
                    if let search = state.lastSearch {
                        Divider().frame(height: 30)
                        SearchResultFigure(search: search)
                    }
                    Spacer(minLength: 0)
                }
                LatestFilingRow(state: state)
            }

            FooterRow(context: context)
        }
        .padding(14)
        .activityBackgroundTint(Color.black.opacity(0.72))
        .activitySystemActionForegroundColor(.white)
        .widgetURL(CaserDeepLink.alertURL(keywordId: context.attributes.keywordId))
    }

    private var subtitle: String {
        var parts = ["CASER alert"]
        if let scope = context.attributes.scopeSummary, !scope.isEmpty { parts.append(scope) }
        if let unread = context.state.unreadCount, unread > 0 { parts.append("\(unread) unread") }
        return parts.joined(separator: " · ")
    }
}

struct CaserAlertLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CaserAlertAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            let state = context.state
            let searching = state.isSearching && !context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        StatusIcon(state: state)
                            .font(.title3)
                        Text(context.attributes.term)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SearchNowButton(
                        keywordId: context.attributes.keywordId,
                        term: context.attributes.term,
                        isSearching: searching,
                        compact: true
                    )
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let active = state.activeSearch, searching {
                            SearchProgressRow(active: active)
                        } else {
                            HStack(alignment: .top, spacing: 16) {
                                NewFilingsFigure(state: state)
                                if let search = state.lastSearch {
                                    SearchResultFigure(search: search)
                                }
                                Spacer(minLength: 0)
                            }
                            LatestFilingRow(state: state)
                        }
                        FooterRow(context: context)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                StatusIcon(state: state)
            } compactTrailing: {
                CompactTrailing(state: state, searching: searching)
            } minimal: {
                if searching {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Palette.accent)
                } else if state.hasNewFiling {
                    Text(state.newFilingCount, format: .number.notation(.compactName))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.newFiling)
                } else {
                    StatusIcon(state: state)
                }
            }
            .widgetURL(CaserDeepLink.alertURL(keywordId: context.attributes.keywordId))
            .keylineTint(Palette.accent)
        }
    }
}

private struct CompactTrailing: View {
    let state: CaserAlertAttributes.ContentState
    let searching: Bool

    var body: some View {
        Group {
            if let active = state.activeSearch, searching {
                Text("\(active.courtsSearched)/\(active.courtsTotal)")
                    .foregroundStyle(Palette.accent)
            } else if let search = state.lastSearch {
                Text("\(search.matchingFilings.formatted(.number.notation(.compactName)))/\(search.filingsSearched.formatted(.number.notation(.compactName)))")
                    .foregroundStyle(search.matchingFilings > 0 ? Palette.newFiling : .primary)
            } else if let last = state.lastCheckedAt {
                Text(last, style: .relative)
            } else {
                Text("--")
            }
        }
        .font(.caption2.weight(.semibold).monospacedDigit())
        .lineLimit(1)
        .frame(maxWidth: 64)
    }
}
