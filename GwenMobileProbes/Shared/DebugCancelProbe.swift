@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugCancelProbe {
    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "cancel_run.txt")
        report.add("KONFIG", "schluessel=\(view.settings.isConfigured) chat=\(view.settings.chatModel) "
                   + "bild=\(view.settings.imageModel)")
        let known = Set(view.store.conversations.map(\.id))
        await runCase(view, report: report, label: "PREIS", busyKey: "price_working",
                      sentence: "Was kostet ein MacBook Pro 16 Zoll gerade im Internet?")
        await runCase(view, report: report, label: "BILD", busyKey: "generating_image",
                      sentence: "Zeichne ein Bild von einem einsamen Leuchtturm bei Nacht.")
        await runCase(view, report: report, label: "CHAT", busyKey: "", waitStreaming: true,
                      sentence: "Erzähl mir eine lange Geschichte über einen Leuchtturm bei Nacht.")
        await chainCase(view, report: report)
        var dropped = 0
        for conversation in view.store.conversations where !known.contains(conversation.id) {
            if view.store.removeConversation(conversation.id) != nil { dropped += 1 }
        }
        report.add("AUFRAEUMEN", "probe_chats_entfernt=\(dropped) chats=\(view.store.conversations.count)")
        flowLog.info("ABBRUCHPROBE fertig")
    }

    private static func runCase(_ view: ChatView, report: SweepReport, label: String, busyKey: String,
                                waitStreaming: Bool = false, sentence: String) async {
        view.store.newConversation()
        let known = Set(view.store.current?.messages.map(\.id) ?? [])
        view.input = sentence
        view.probeStartSend()
        let reached = await wait(seconds: 25) {
            if waitStreaming { return view.probeStreaming || view.probeStreamedChars >= 40 }
            return !busyKey.isEmpty && view.probeBusyLabel == L.t(busyKey)
        }
        guard reached else {
            let shown = TextLine.oneLine(view.probeBusyLabel, limit: 40)
            view.probeStopRun()
            _ = await wait(seconds: 10) { !view.probeRunInFlight && !view.probeBusy }
            report.add(label, "phase_erreicht=false laufend=\(view.probeRunInFlight) label=\(shown)")
            return
        }
        let streamedBefore = view.probeStreamedChars
        let atCancel = ContinuousClock.now
        view.probeStopRun()
        let outcome = await afterCancel(view, known: known, atCancel: atCancel)
        report.add(label, "phase_erreicht=\(reached) sofort_idle=\(outcome.idle) ms_bis_idle=\(outcome.ms) "
                   + "nachlauf=\(outcome.still) antworten=\(outcome.fresh.count) fehler=\(outcome.errors) "
                   + "bilder=\(outcome.pictures) "
                   + "stream_zeichen_vor_abbruch=\(streamedBefore) "
                   + "behalten_zeichen=\(outcome.fresh.map(\.text.count).reduce(0, +)) "
                   + "kette=\(view.probeLastPlan?.traceLine ?? "-") "
                   + "text=\(TextLine.oneLine(outcome.fresh.first?.text ?? "-", limit: 120))")
    }

    private static func chainCase(_ view: ChatView, report: SweepReport) async {
        view.store.newConversation()
        let known = Set(view.store.current?.messages.map(\.id) ?? [])
        view.input = "Zeichne ein Bild von einem Leuchtturm, und suche dann die günstigsten Preise "
            + "für eine PlayStation 5."
        view.probeStartSend()
        let reached = await wait(seconds: 25) { view.probeBusyLabel == L.t("generating_image") }
        let planned = view.probeLastPlan?.traceLine ?? "-"
        guard reached else {
            view.probeStopRun()
            _ = await wait(seconds: 10) { !view.probeRunInFlight && !view.probeBusy }
            report.add("KETTE", "phase_erreicht=false kette=\(planned)")
            return
        }
        let atCancel = ContinuousClock.now
        view.probeStopRun()
        let outcome = await afterCancel(view, known: known, atCancel: atCancel)
        let note = outcome.fresh.contains { $0.text.contains("Angehalten") }
        report.add("KETTE", "phase_erreicht=\(reached) sofort_idle=\(outcome.idle) ms_bis_idle=\(outcome.ms) "
                   + "kette=\(planned) hinweis=\(note) antworten=\(outcome.fresh.count) fehler=\(outcome.errors) "
                   + "bilder=\(outcome.pictures) "
                   + "text=\(TextLine.oneLine(outcome.fresh.map(\.text).joined(separator: " | "), limit: 120))")
    }

    private struct CancelOutcome {
        let idle: Bool
        let ms: Int
        let fresh: [ChatMessage]
        let errors: Int
        let pictures: Int
        let still: Bool
    }

    private static func afterCancel(_ view: ChatView, known: Set<UUID>,
                                    atCancel: ContinuousClock.Instant) async -> CancelOutcome {
        let idle = await wait(seconds: 10) { !view.probeRunInFlight && !view.probeBusy && !view.probeStreaming }
        let ms = msOf(atCancel.duration(to: .now))
        _ = await ProbeWait.untilSettled(2) { (view.store.current?.messages ?? []).count }
        let messages = view.store.current?.messages ?? []
        let fresh = messages.filter { !known.contains($0.id) && $0.role == .assistant }
        let errors = fresh.filter { $0.text.contains(AnswerError.marker) }.count
        let pictures = fresh.flatMap { $0.outImages ?? [] }.count
        let still = view.probeRunInFlight || view.probeBusy || view.probeStreaming
        return CancelOutcome(idle: idle, ms: ms, fresh: fresh, errors: errors,
                             pictures: pictures, still: still)
    }

    private static func wait(seconds: Double, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }
}
#endif
