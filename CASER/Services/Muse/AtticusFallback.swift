import Foundation
import os.log
#if canImport(FoundationModels)
import FoundationModels
#endif

private let fallbackLogger = Logger(subsystem: "com.caser.app", category: "AtticusFallback")

enum AtticusSource: String, Codable, Sendable {
    case muse
    case privateCloudCompute
    case onDevice
    case docket

    var note: String? {
        switch self {
        case .muse:
            return nil
        case .privateCloudCompute:
            return "Meta Muse couldn't be reached, so Apple Private Cloud Compute wrote this from the docket."
        case .onDevice:
            return "Meta Muse couldn't be reached, so Apple Intelligence on this iPhone wrote this from the docket."
        case .docket:
            return "Meta Muse couldn't be reached, so this summary comes straight from the docket."
        }
    }
}

enum AtticusFallback {
    @MainActor
    static func insights(for context: MuseCaseContext) async -> (CaseInsights, AtticusSource) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let (draft, source) = await AppleAtticus.generate(
               AppleInsightsDraft.self,
               instructions: AppleAtticus.insightsInstructions,
               prompt: AppleAtticus.docketPrompt(context)
           ) {
            let insights = CaseInsights(
                summary: draft.summary,
                filingExplained: draft.filingExplained,
                keyTerms: draft.keyTerms.map { CaseInsights.KeyTerm(term: $0.term, meaning: $0.meaning) },
                whatToWatch: draft.whatToWatch
            )
            if !insights.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (insights, source)
            }
        }
        #endif
        return (DocketBrief(context: context).insights, .docket)
    }

    @MainActor
    static func research(for context: MuseCaseContext) async -> (CaseResearch, AtticusSource) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let (draft, source) = await AppleAtticus.generate(
               AppleAboutDraft.self,
               instructions: AppleAtticus.aboutInstructions,
               prompt: AppleAtticus.docketPrompt(context)
           ) {
            let about = CaseAbout(
                story: draft.story,
                whosWho: draft.whosWho.map { CaseAbout.Person(name: $0.name, role: $0.role) },
                whereItStands: draft.whereItStands,
                timeline: draft.timeline.map { CaseAbout.TimelineEvent(date: $0.date, event: $0.event) }
            )
            if about.hasReadableStory {
                return (CaseResearch(brief: about.story, citations: [], about: about), source)
            }
        }
        #endif
        let about = DocketBrief(context: context).about
        return (CaseResearch(brief: about.story, citations: [], about: about), .docket)
    }

    @MainActor
    static func answer(
        _ question: String,
        about context: MuseCaseContext,
        notes: MuseCaseNotes,
        history: [MuseFollowUpTurn]
    ) async -> CaseAnswer {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let (text, source) = await AppleAtticus.respond(
               instructions: AppleAtticus.questionInstructions,
               prompt: AppleAtticus.questionPrompt(question, context: context, notes: notes, history: history)
           ) {
            return CaseAnswer(text: text, citations: [], source: source)
        }
        #endif
        return CaseAnswer(text: DocketBrief(context: context).answer, citations: [], source: .docket)
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct AppleInsightsDraft {
    @Guide(description: "Two or three plain-English sentences on what this filing is.")
    var summary: String

    @Guide(description: "Two or three plain-English sentences on what this filing means for the people involved.")
    var filingExplained: String

    @Guide(description: "Legal terms from the docket a non-lawyer may not know, each with a one-sentence meaning.", .maximumCount(5))
    var keyTerms: [AppleTerm]

    @Guide(description: "Short plain-English things to watch for next in this case.", .maximumCount(4))
    var whatToWatch: [String]
}

@available(iOS 26.0, *)
@Generable
struct AppleTerm {
    @Guide(description: "The legal term as written in the docket.")
    var term: String

    @Guide(description: "A one-sentence plain-English meaning.")
    var meaning: String
}

@available(iOS 26.0, *)
@Generable
struct AppleAboutDraft {
    @Guide(description: "Three to five plain-English sentences telling the story of this case using only the docket facts given.")
    var story: String

    @Guide(description: "People and organizations named in the docket and their role in the case.", .maximumCount(8))
    var whosWho: [ApplePerson]

    @Guide(description: "One or two sentences on where the case stands based on the latest docket entry.")
    var whereItStands: String

    @Guide(description: "Dated events that appear in the docket, oldest first. Empty if none are given.", .maximumCount(6))
    var timeline: [AppleEvent]
}

@available(iOS 26.0, *)
@Generable
struct ApplePerson {
    var name: String
    var role: String
}

@available(iOS 26.0, *)
@Generable
struct AppleEvent {
    @Guide(description: "The date exactly as it appears in the docket.")
    var date: String
    var event: String
}

@available(iOS 26.0, *)
@MainActor
enum AppleAtticus {
    static let insightsInstructions = """
    You are Atticus, a plain-English guide to US court filings for people who are not lawyers. \
    Explain only what the docket facts given say. Never invent names, dates, amounts or outcomes. \
    This is information, not legal advice.
    """

    static let aboutInstructions = """
    You are Atticus, a plain-English guide to US court cases for people who are not lawyers. \
    Describe the case using only the docket facts given. You cannot search the web, so never invent \
    news, names, dates, amounts or outcomes. This is information, not legal advice.
    """

    static let questionInstructions = """
    You are Atticus, a plain-English guide to US court cases for people who are not lawyers. \
    Answer the question in a short paragraph using only the docket facts and notes given. If they \
    don't answer it, say so and suggest checking the docket. Never invent facts. This is information, \
    not legal advice.
    """

    private static var options: GenerationOptions { GenerationOptions(temperature: 0.3) }

    static func docketPrompt(_ context: MuseCaseContext, limit: Int = 3000) -> String {
        var lines = ["Case: \(context.title)"]
        if !context.court.isEmpty { lines.append("Court: \(context.court)") }
        if !context.caseNumber.isEmpty { lines.append("Case number: \(context.caseNumber)") }
        if !context.filedDate.isEmpty { lines.append("Docket entry date: \(context.filedDate)") }
        if !context.caseType.isEmpty { lines.append("Case type: \(context.caseType)") }
        if !context.parties.isEmpty { lines.append("Parties: \(context.parties.prefix(12).joined(separator: "; "))") }
        if !context.docketText.isEmpty { lines.append("Docket entry: \(context.docketText.prefix(limit))") }
        return lines.joined(separator: "\n")
    }

    static func questionPrompt(
        _ question: String,
        context: MuseCaseContext,
        notes: MuseCaseNotes,
        history: [MuseFollowUpTurn]
    ) -> String {
        var parts = [docketPrompt(context, limit: 2000)]
        if !notes.summary.isEmpty { parts.append("Notes: \(notes.summary.prefix(800))") }
        for turn in history.suffix(2) {
            parts.append("Earlier question: \(turn.question.prefix(300))\nEarlier answer: \(turn.answer.prefix(600))")
        }
        parts.append("Question: \(question)")
        return parts.joined(separator: "\n\n")
    }

    static func generate<Draft: Generable>(
        _ type: Draft.Type,
        instructions: String,
        prompt: String
    ) async -> (Draft, AtticusSource)? {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            if case .available = model.availability {
                do {
                    let session = LanguageModelSession(model: model, instructions: instructions)
                    let draft = try await session.respond(
                        to: Prompt { prompt },
                        generating: type,
                        options: options,
                        contextOptions: ContextOptions(includeSchemaInPrompt: true, reasoningLevel: .moderate)
                    ).content
                    return (draft, .privateCloudCompute)
                } catch {
                    fallbackLogger.info("Private Cloud Compute failed; trying the on-device model")
                }
            }
        }
        #endif
        guard SystemLanguageModel.default.isAvailable else { return nil }
        do {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let draft = try await session.respond(to: prompt, generating: type, options: options).content
            return (draft, .onDevice)
        } catch {
            fallbackLogger.info("On-device model failed; using the docket summary")
            return nil
        }
    }

    static func respond(instructions: String, prompt: String) async -> (String, AtticusSource)? {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            if case .available = model.availability {
                do {
                    let session = LanguageModelSession(model: model, instructions: instructions)
                    let text = try await session.respond(
                        to: Prompt { prompt },
                        options: options,
                        contextOptions: ContextOptions(includeSchemaInPrompt: false, reasoningLevel: .moderate)
                    ).content
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return (text, .privateCloudCompute)
                    }
                } catch {
                    fallbackLogger.info("Private Cloud Compute failed; trying the on-device model")
                }
            }
        }
        #endif
        guard SystemLanguageModel.default.isAvailable else { return nil }
        do {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let text = try await session.respond(to: prompt, options: options).content
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : (text, .onDevice)
        } catch {
            fallbackLogger.info("On-device model failed; using the docket summary")
            return nil
        }
    }
}
#endif

struct DocketBrief {
    let context: MuseCaseContext
    let fields: [String: String]

    init(context: MuseCaseContext) {
        self.context = context
        fields = Self.parseFields(context.docketText)
    }

    var chapter: String? { fields["chapter"].flatMap { $0.split(separator: " ").first.map(String.init) } }
    var trustee: String? { fields["trustee"] }

    var isBankruptcy: Bool {
        fields["type"]?.lowercased() == "bk" || chapter != nil || context.court.localizedCaseInsensitiveContains("bankruptcy")
    }

    var kind: String {
        if isBankruptcy {
            return chapter.map { "Chapter \($0) bankruptcy case" } ?? "bankruptcy case"
        }
        switch fields["type"]?.lowercased() {
        case "cv": return "civil case"
        case "cr": return "criminal case"
        case "ap": return "adversary proceeding"
        default: return context.caseType.isEmpty ? "court case" : "\(context.caseType) case"
        }
    }

    var dateText: String? {
        guard let date = try? Date(context.filedDate, strategy: .iso8601.year().month().day()) else { return nil }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = TimeZone(identifier: "UTC") ?? .current
        return date.formatted(style)
    }

    var opening: String {
        var sentence = "\(context.title) is a \(kind)"
        if !context.court.isEmpty { sentence += " in \(context.court)" }
        if !sentence.hasSuffix(".") { sentence += "." }
        if let dateText { sentence += " This docket entry is dated \(dateText)." }
        return sentence
    }

    var docketExcerpt: String {
        let text = context.docketText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, fields.isEmpty else { return "" }
        return text.count > 400 ? String(text.prefix(400)) + "…" : text
    }

    var chapterExplained: String {
        switch chapter {
        case "7":
            return "In Chapter 7, a trustee collects and sells property that isn't protected by law and pays creditors from it. Most remaining qualifying debts are then wiped out by a discharge."
        case "11":
            return "In Chapter 11, the debtor usually keeps running its business or managing its property while it proposes a plan to repay creditors over time."
        case "13":
            return "In Chapter 13, a person with regular income keeps their property and repays some or all of their debts through a three- to five-year plan run by a trustee."
        case "12":
            return "Chapter 12 lets family farmers and fishermen repay debts through a plan while keeping their operations running."
        case "9":
            return "Chapter 9 lets a city, county or other public body restructure its debts."
        case "15":
            return "Chapter 15 coordinates a US court with a bankruptcy case already underway in another country."
        default:
            return isBankruptcy
                ? "Bankruptcy is a federal court process that pauses most collection efforts while a person's or company's debts are sorted out."
                : "Each docket entry records a filing, order or event in the case."
        }
    }

    var insights: CaseInsights {
        var summary = opening
        if let trustee { summary += " The trustee is \(trustee)." }
        var terms: [CaseInsights.KeyTerm] = []
        if isBankruptcy {
            terms.append(.init(term: "Automatic stay", meaning: "A court order that stops most creditors from collecting while the case is open."))
            if trustee != nil {
                terms.append(.init(term: "Trustee", meaning: "The person appointed to oversee the case and, in some chapters, collect and sell property for creditors."))
            }
            if context.docketText.localizedCaseInsensitiveContains("schedules") {
                terms.append(.init(term: "Schedules", meaning: "Forms listing the debtor's property, debts, income and expenses."))
            }
            terms.append(.init(term: "Discharge", meaning: "The court order that releases the debtor from paying qualifying debts."))
        } else {
            terms.append(.init(term: "Docket", meaning: "The court's running list of everything filed and decided in a case."))
        }
        var watch: [String] = []
        if isBankruptcy {
            watch.append("The meeting of creditors, where the debtor answers questions under oath.")
            if chapter == "13" || chapter == "11" { watch.append("Whether the court confirms the repayment plan.") }
            watch.append("Deadlines for creditors to file claims or object to the discharge.")
        }
        watch.append("New entries on the docket, which can set deadlines or hearings.")
        return CaseInsights(
            summary: summary,
            filingExplained: [chapterExplained, docketExcerpt].filter { !$0.isEmpty }.joined(separator: " "),
            keyTerms: terms,
            whatToWatch: watch
        )
    }

    var about: CaseAbout {
        var people = context.parties.prefix(6).map { CaseAbout.Person(name: $0, role: "Named in the case") }
        if let trustee { people.append(CaseAbout.Person(name: trustee, role: "Trustee")) }
        var stands = "The latest docket entry CASER has"
        stands += dateText.map { " is from \($0)." } ?? " is shown below."
        if !docketExcerpt.isEmpty { stands += " It reads: \(docketExcerpt)" }
        var timeline: [CaseAbout.TimelineEvent] = []
        if let dateText {
            timeline.append(CaseAbout.TimelineEvent(date: dateText, event: context.court.isEmpty ? "Docket entry filed" : "Docket entry filed in \(context.court)"))
        }
        return CaseAbout(
            story: [opening, chapterExplained].joined(separator: " "),
            whosWho: people,
            whereItStands: stands,
            timeline: timeline
        )
    }

    var answer: String {
        "Atticus can't answer new questions right now. Here's what the docket shows: \(insights.summary) \(chapterExplained) Ask again in a little while for a full answer."
    }

    static func parseFields(_ text: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|\s)([A-Z][A-Za-z]{1,15}):\s"#) else { return [:] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return [:] }
        var result: [String: String] = [:]
        for (index, match) in matches.enumerated() {
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let value = ns.substring(with: NSRange(location: start, length: max(0, end - start)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { result[key] = value }
        }
        if let trustee = result["trustee"] {
            result["trustee"] = trustee
                .replacingOccurrences(of: #"\s+(Schedules|Plan|Deficiencies)\b.*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            let names = result["trustee"]?.components(separatedBy: ", ") ?? []
            if names.count == 2 { result["trustee"] = "\(names[1]) \(names[0])" }
        }
        return result
    }
}
