import Foundation
import Observation

enum MuseLoadState<Value: Equatable>: Equatable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct CaseFollowUp: Identifiable, Equatable {
    let id = UUID()
    let question: String
    let answer: CaseAnswer
}

@MainActor
@Observable
final class CaseInsightsModel {
    private(set) var insights: MuseLoadState<CaseInsights> = .idle
    private(set) var research: MuseLoadState<CaseResearch> = .idle
    private(set) var followUps: [CaseFollowUp] = []
    private(set) var researchUpdatedAt: Date?
    private(set) var isAsking = false
    private(set) var liveQuestion: String?
    private(set) var liveAnswer = ""
    private(set) var liveThinking = ""
    private(set) var liveTool = ""
    var askError: String?

    var isStreamingAnswer: Bool { isAsking && liveQuestion != nil }

    @ObservationIgnored private let cacheKey: String
    @ObservationIgnored private let context: MuseCaseContext

    init(entry: CaseEntry) {
        cacheKey = entry.id
        context = MuseCaseContext(entry: entry)
        if let record = AtticusCaseStore.shared.record(for: cacheKey) {
            if let cached = record.insights {
                insights = .loaded(cached)
            }
            if let cached = record.research, cached.about.hasReadableStory {
                research = .loaded(cached)
                researchUpdatedAt = record.researchUpdatedAt
            }
            followUps = record.followUps.map { CaseFollowUp(question: $0.question, answer: $0.answer) }
        }
    }

    var hasConsent: Bool {
        AIDisclaimerConsent.shared.hasAcceptedCurrentVersion
    }

    func load() async {
        guard hasConsent else { return }
        async let insightsLoad: Void = loadInsights()
        async let researchLoad: Void = loadResearch()
        _ = await (insightsLoad, researchLoad)
    }

    func retryInsights() async {
        guard hasConsent, !insights.isLoading else { return }
        insights = .idle
        await loadInsights()
    }

    func retryResearch() async {
        guard hasConsent, !research.isLoading else { return }
        research = .idle
        await loadResearch()
    }

    func ask(_ raw: String) async {
        guard hasConsent, !isAsking else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let question: String
        switch PromptGuard.validateUserInput(trimmed) {
        case .allowed(let sanitized):
            question = String(sanitized.prefix(1000))
        case .blocked(let message):
            askError = message
            return
        }

        isAsking = true
        askError = nil
        liveQuestion = question
        liveAnswer = ""
        liveThinking = ""
        liveTool = ""
        defer {
            isAsking = false
            liveQuestion = nil
        }

        let notes = MuseCaseNotes(
            summary: String((insights.value?.summary ?? "").prefix(3000)),
            research: String((research.value?.brief ?? "").prefix(8000))
        )
        let history = followUps.suffix(3).map {
            MuseFollowUpTurn(question: $0.question, answer: String($0.answer.text.prefix(4000)))
        }

        var citations: [MuseCitation] = []
        var thinking = ""
        var toolUsed = ""
        do {
            let stream = await MuseClient.shared.askStreaming(question, about: context, notes: notes, history: history)
            for try await event in stream {
                switch event.kind {
                case .text(let delta):
                    liveAnswer += delta
                case .thinking(let delta):
                    liveThinking += delta
                    thinking = liveThinking
                case .tool(let name):
                    liveTool = name
                    toolUsed = name
                case .sources(let found):
                    citations = found
                case .done:
                    break
                }
            }
        } catch is CancellationError {
            return
        } catch {
            if liveAnswer.isEmpty {
                do {
                    let answer = try await MuseClient.shared.ask(question, about: context, notes: notes, history: history)
                    followUps.append(CaseFollowUp(question: question, answer: answer))
                    AtticusCaseStore.shared.update(cacheKey) {
                        $0.followUps.append(AtticusFollowUpRecord(question: question, answer: answer))
                    }
                    return
                } catch is CancellationError {
                    return
                } catch {
                    askError = MuseError.message(for: error)
                    return
                }
            }
            askError = MuseError.message(for: error)
        }

        let answerText = liveAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answerText.isEmpty else { return }
        let answer = CaseAnswer(text: answerText, citations: citations, thinking: thinking, toolUsed: toolUsed)
        followUps.append(CaseFollowUp(question: question, answer: answer))
        AtticusCaseStore.shared.update(cacheKey) {
            $0.followUps.append(AtticusFollowUpRecord(question: question, answer: answer))
        }
    }

    private func loadInsights() async {
        if case .loaded = insights { return }
        guard !insights.isLoading else { return }
        insights = .loading
        do {
            let value = try await MuseClient.shared.insights(for: context)
            AtticusCaseStore.shared.update(cacheKey) { $0.insights = value }
            insights = .loaded(value)
        } catch is CancellationError {
            insights = .idle
        } catch {
            insights = .failed(MuseError.message(for: error))
        }
    }

    private func loadResearch() async {
        if case .loaded = research { return }
        guard !research.isLoading else { return }
        research = .loading
        do {
            let value = try await MuseClient.shared.research(for: context)
            guard value.about.hasReadableStory else { throw MuseError.unavailable }
            let updatedAt = Date()
            AtticusCaseStore.shared.update(cacheKey) {
                $0.research = value
                $0.researchUpdatedAt = updatedAt
            }
            research = .loaded(value)
            researchUpdatedAt = updatedAt
        } catch is CancellationError {
            research = .idle
        } catch {
            research = .failed(MuseError.message(for: error))
        }
    }
}
