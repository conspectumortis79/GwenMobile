import GwenMobileKit
import SwiftUI

extension ChatView {
    @MainActor
    private func finishDeskAnswer(_ text: String, artifacts: AnswerArtifacts = AnswerArtifacts(),
                                  convID: UUID, started: Date, slot: AnswerSlot? = nil,
                                  announce: Bool = true) {
        finishAnswer(text, artifacts: artifacts, model: settings.chatModel, convID: convID,
                     started: started, slot: slot, announce: announce)
    }

    @MainActor
    private func deskOutcome<Outcome>(busy key: String, carriedOut: (Outcome) -> Bool,
                                      _ work: @MainActor () async -> Outcome) async -> Outcome? {
        guard !Task.isCancelled else { return nil }
        let outcome = await withBusy(L.t(key), work)
        guard carriedOut(outcome) || !Task.isCancelled else { return nil }
        return outcome
    }

    @MainActor func runCallFlow(_ request: ContactRequest, convID: UUID, started: Date,
                                        slot: AnswerSlot? = nil) async {
        guard let outcome = await deskOutcome(busy: "call_working", carriedOut: \.placed, {
            await callDesk.runner().run(request)
        }) else { return }
        flowMarkPersonal("ANRUF \(request.stepWords) \(outcome.trace)")
        finishDeskAnswer(outcome.text, convID: convID, started: started, slot: slot,
                         announce: !outcome.placed)
    }

    @MainActor func placeCall(_ number: DialNumber) async {
        guard !Task.isCancelled else { return }
        guard !callPlacing, let convID = store.current?.id else { return }
        callPlacing = true
        defer { callPlacing = false }
        let dialer = callDesk.dialer
        let start = await withBusy(L.t("call_link_working")) { await dialer.place(number) }
        guard start != .failed || !Task.isCancelled else { return }
        flowMarkPersonal("ANRUF tipp nummer=\(number.masked) weg=\(dialer.way) start=\(start.rawValue)")
        let target = CallTarget(name: number.digits, label: "", number: number)
        let text = start == .failed
            ? L.fmt("call_link_failed", number.digits)
            : CallAnswer.started(start, target: target, note: .none)
        finishDeskAnswer(text, convID: convID, started: Date(), announce: start == .failed)
    }

    @MainActor func runMessageFlow(_ request: MessageRequest, convID: UUID, started: Date,
                                           slot: AnswerSlot? = nil) async {
        guard let outcome = await deskOutcome(busy: "message_working", carriedOut: \.sent, {
            await messageDesk.runner().run(request)
        }) else { return }
        flowMarkPersonal("NACHRICHT \(request.recipient.stepWords) \(outcome.trace)")
        finishDeskAnswer(outcome.text, convID: convID, started: started, slot: slot)
    }

    @MainActor func runReminderFlow(_ request: ReminderRequest, convID: UUID,
                                            started: Date, slot: AnswerSlot? = nil) async {
        guard let outcome = await deskOutcome(busy: "rem_working", carriedOut: \.changed, {
            await reminderDesk.runner().run(request)
        }) else { return }
        flowMarkPersonal("ERINNERUNG \(request.stepWords) \(outcome.trace)")
        finishDeskAnswer(outcome.text, artifacts: AnswerArtifacts(reminderRef: outcome.ref),
                         convID: convID, started: started, slot: slot)
    }

    @MainActor func runTimerFlow(_ request: TimerRequest, convID: UUID, started: Date,
                                         slot: AnswerSlot? = nil) async {
        guard let setting = await deskOutcome(busy: "timer_working", carriedOut: \.isSet, {
            await timerDesk.setter.set(request)
        }) else { return }
        flowMarkPersonal("TIMER \(request.stepWords) \(setting.trace)")
        finishDeskAnswer(TimerAnswer.result(setting, request: request),
                         convID: convID, started: started, slot: slot)
    }

    @MainActor func runMusicFlow(_ request: MusicRequest, convID: UUID, started: Date,
                                         slot: AnswerSlot? = nil) async {
        guard let outcome = await deskOutcome(busy: "music_working", carriedOut: \.soundsNow, {
            await musicDesk.runner(preferred: settings.music.service).run(request)
        }) else { return }
        musicDesk.remember(outcome)
        flowMarkPersonal("MUSIK \(request.stepWords) \(outcome.trace)")
        finishDeskAnswer(outcome.text, convID: convID, started: started, slot: slot,
                         announce: !outcome.soundsNow)
    }

}
