@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugDetailProbe {
    static let opening = "bitte die aktuellen Nachrichten aus Berlin anzeigen"
    static let followUp = "bitte je Meldung mehr Information dazu"
    static let textLimit = 6000

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "detail_followup.txt")
        report.add("KONFIG", "chat=\(view.settings.chatModel) kappe_alt=\(ConversationTranscript.defaultCap) "
                   + "kappe_antwort=\(ConversationTranscript.defaultAnswerCap) "
                   + "kompakt=\(AnswerLength.compactWords)")
        view.store.newConversation()
        let first = await turn(opening, round: 1, view: view, report: report)
        let second = await turn(followUp, round: 2, view: view, report: report)
        report.add("VERGLEICH", "woerter_vorher=\(words(first)) woerter_nachher=\(words(second)) "
                   + "laenger=\(words(second) > words(first))")
    }

    private static func turn(_ sentence: String, round: Int, view: ChatView,
                             report: SweepReport) async -> String {
        let before = view.store.current?.messages ?? []
        let transcript = ConversationTranscript.from(messages: before)
        view.probeLastPlan = nil
        flowMark("DETAIL runde=\(round)")
        await view.ask(sentence)
        let plan = view.probeLastPlan
        let length = AnswerLengthPlan.fitting(before + [ChatMessage(role: .user, text: sentence)],
                                              detailWish: plan?.primary.detailWish ?? false)
        let answers = Array((view.store.current?.messages ?? []).dropFirst(before.count + 1))
            .filter { $0.role == .assistant }
        let text = answers.map(\.text).joined(separator: "\n\n")
        let sources = answers.reduce(0) { $0 + ($1.sources?.count ?? 0) }
        report.add("R\(round)_FRAGE", sentence)
        report.add("R\(round)_PLAN", "kette=\(plan?.traceLine ?? "-") \(length.traceLine) "
                   + "verlauf_zeichen=\(transcript.count) vorige_antwort_ganz=\(carriesWhole(before, transcript))")
        report.add("R\(round)_ANTWORT", "blasen=\(answers.count) zeichen=\(text.count) woerter=\(words(text)) "
                   + "punkte=\(AnswerItems.count(in: text)) quellen=\(sources)")
        report.add("R\(round)_TEXT", TextLine.oneLine(text, limit: textLimit))
        return text
    }

    private static func carriesWhole(_ messages: [ChatMessage], _ transcript: String) -> Bool {
        guard let answer = messages.last(where: { $0.role == .assistant }) else { return false }
        return transcript.contains(answer.text.replacingOccurrences(of: "\n", with: " "))
    }

    private static func words(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
#endif
