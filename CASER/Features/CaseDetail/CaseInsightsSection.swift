import SwiftUI
import UIKit

struct CaseInsightsSection: View {
    let model: CaseInsightsModel
    @State private var showConsent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AtticusHeader()

            if model.hasConsent {
                InsightsCard(model: model)
                ResearchCard(model: model)
                AtticusFooter()
            } else {
                consentCard
            }
        }
        .sheet(isPresented: $showConsent) {
            AIDisclaimerSheet(
                onAccept: {
                    showConsent = false
                    Task { await model.load() }
                },
                onDecline: { showConsent = false }
            )
        }
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Atticus can explain this filing in plain English, show where the case stands, and find recent news about it.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showConsent = true
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Turn On Atticus")
                    Spacer()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.black)
                .padding(14)
                .background(Color.caserAccent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the Atticus terms before explaining this case")
        }
        .atticusCard()
    }
}

struct CaseFollowUpSection: View {
    let model: CaseInsightsModel

    var body: some View {
        if model.hasConsent {
            VStack(alignment: .leading, spacing: 12) {
                ArtifactSectionTitle(title: "Ask Atticus", icon: "sparkles")

                ForEach(model.followUps) { followUp in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(followUp.question)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.caserAccent)
                        MuseMarkdownText(markdown: followUp.answer.text)
                        CitationList(citations: followUp.answer.citations)
                    }
                    .atticusCard()
                }

                if model.isStreamingAnswer, let question = model.liveQuestion {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(question)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.caserAccent)
                        if !model.liveThinking.isEmpty {
                            ThinkingArtifact(thinking: model.liveThinking)
                        }
                        if model.liveAnswer.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small).tint(.white)
                                Text(model.liveTool.isEmpty ? "Atticus is looking into it…" : "Atticus is searching related dockets…")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        } else {
                            HStack(alignment: .bottom, spacing: 4) {
                                MuseMarkdownText(markdown: model.liveAnswer)
                                StreamingCursor()
                            }
                        }
                    }
                    .atticusCard()
                    .accessibilityElement(children: .combine)
                }

                if let error = model.askError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct AtticusHeader: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.caserAccent)
            Text("Atticus")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Text("Powered by Meta Muse")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct InsightsCard: View {
    let model: CaseInsightsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.insights {
            case .idle, .loading:
                MuseSkeleton(label: "Atticus is reading this filing")
            case .failed(let message):
                RetryMessage(message: message) { await model.retryInsights() }
            case .loaded(let insights):
                ArtifactSectionTitle(title: "What This Filing Is", icon: "doc.text.magnifyingglass")
                Text(insights.summary)
                    .font(.body)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if !insights.filingExplained.isEmpty {
                    InsightBlock(title: "What This Filing Means") {
                        Text(insights.filingExplained)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !insights.keyTerms.isEmpty {
                    InsightBlock(title: "Terms in This Entry") {
                        ForEach(insights.keyTerms, id: \.self) { item in
                            Text("\(Text(item.term).bold()) — \(item.meaning)")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !insights.whatToWatch.isEmpty {
                    InsightBlock(title: "What to Watch") {
                        ForEach(insights.whatToWatch, id: \.self) { item in
                            Text("• \(item)")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .atticusCard()
        .animation(.easeInOut(duration: 0.25), value: model.insights)
    }
}

private struct ResearchCard: View {
    let model: CaseInsightsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.research {
            case .idle, .loading:
                ArtifactSectionTitle(title: "About This Case", icon: "text.book.closed.fill")
                MuseSkeleton(label: "Atticus is searching for the story behind this case")
            case .failed(let message):
                ArtifactSectionTitle(title: "About This Case", icon: "text.book.closed.fill")
                RetryMessage(message: message) { await model.retryResearch() }
            case .loaded(let research):
                AboutCaseArtifact(about: research.about, citations: research.citations, artwork: model.artwork) {
                    await model.loadArtwork()
                }

                if !research.about.whosWho.isEmpty {
                    ArtifactSectionTitle(title: "Who's Who", icon: "person.2.fill")
                    WhosWhoArtifact(people: research.about.whosWho)
                }

                if !research.about.whereItStands.isEmpty {
                    ArtifactSectionTitle(title: "Where It Stands", icon: "flag.fill")
                    CitedProse(text: research.about.whereItStands, segments: research.about.whereItStandsSegments, citations: research.citations)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !research.about.timeline.isEmpty {
                    ArtifactSectionTitle(title: "Timeline", icon: "calendar.badge.clock")
                    TimelineArtifact(events: research.about.timeline)
                }

                if !research.about.inTheNews.isEmpty {
                    ArtifactSectionTitle(title: "In the News", icon: "newspaper.fill")
                    NewsArtifact(items: research.about.inTheNews)
                }

                ThinkingArtifact(thinking: research.thinking)
                SourceCards(citations: research.citations)

                HStack(spacing: 6) {
                    if let updatedAt = model.researchUpdatedAt {
                        Text("Updated \(updatedAt.formatted(.relative(presentation: .named)))")
                    }
                    Spacer()
                    Button {
                        Task { await model.retryResearch() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .foregroundStyle(Color.caserAccent)
                    .frame(minHeight: 44)
                    .accessibilityHint("Searches again for the latest news about this case")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            }
        }
        .atticusCard()
        .animation(.easeInOut(duration: 0.25), value: model.research)
    }
}

private struct AtticusFooter: View {
    var body: some View {
        Text("Information only, not legal advice. Atticus can make mistakes, so check the docket and official sources.")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct InsightBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            content
        }
    }
}

private struct RetryMessage: View {
    let message: String
    let retry: @MainActor () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await retry() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.caserAccent)
            }
            .frame(minHeight: 44)
        }
    }
}

private struct MuseSkeleton: View {
    let label: String
    @State private var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(dimmed ? 0.06 : 0.14))
                    .frame(height: 12)
                    .frame(maxWidth: index == 3 ? 160 : .infinity, alignment: .leading)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

struct MuseMarkdownText: View {
    let markdown: String

    var body: some View {
        Text(attributed)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.88))
            .tint(Color.caserAccent)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard let safe = URLValidator.safeURL(url), safe.scheme?.lowercased() == "https" else {
                    return .discarded
                }
                return .systemAction(safe)
            })
    }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}

private struct CitationList: View {
    let citations: [MuseCitation]

    var body: some View {
        if !citations.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sources")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
                ForEach(citations, id: \.self) { citation in
                    Button {
                        guard let url = URLValidator.safeURL(citation.url), url.scheme?.lowercased() == "https" else { return }
                        UIApplication.shared.open(url)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "link")
                                .font(.caption2)
                            Text(citation.title)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.caserAccent)
                        .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the source in Safari")
                }
            }
        }
    }
}

private extension View {
    func atticusCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AskAtticusBar: View {
    let model: CaseInsightsModel
    @State private var question = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color.caserAccent)
                Text("Ask Atticus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("Powered by Meta Muse")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            HStack(spacing: 8) {
                TextField("Ask Atticus about this case", text: $question, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .focused($focused)
                    .onSubmit(send)
                    .padding(12)
                    .background(CASERColors.inputBackground, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(canSend ? Color.caserAccent : .white.opacity(0.3))
                }
                .disabled(!canSend)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Send question to Atticus")
            }
        }
        .padding(12)
    }

    private var canSend: Bool {
        !model.isAsking && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        let text = question
        question = ""
        focused = false
        Task { await model.ask(text) }
    }
}
