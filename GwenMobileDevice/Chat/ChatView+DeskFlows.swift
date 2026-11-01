@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func runCallFlow(_ request: ContactRequest, convID: UUID, started: Date,
                                        slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let runner = callDesk.runner()
        let outcome = await withBusy(L.t("call_working")) { await runner.run(request) }
        guard outcome.placed || !Task.isCancelled else { return }
        flowMarkPersonal("ANRUF \(request.stepWords) \(outcome.trace)")
        let model = settings.chatModel
        finishAnswer(outcome.text, model: model, convID: convID, started: started, slot: slot,
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
        finishAnswer(text, model: settings.chatModel, convID: convID, started: Date(),
                     announce: start == .failed)
    }

    @MainActor func runMessageFlow(_ request: MessageRequest, convID: UUID, started: Date,
                                           slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let runner = messageDesk.runner()
        let outcome = await withBusy(L.t("message_working")) { await runner.run(request) }
        guard outcome.sent || !Task.isCancelled else { return }
        flowMarkPersonal("NACHRICHT \(request.recipient.stepWords) \(outcome.trace)")
        let model = settings.chatModel
        finishAnswer(outcome.text, model: model, convID: convID, started: started, slot: slot)
    }

    @MainActor func runReminderFlow(_ request: ReminderRequest, convID: UUID,
                                            started: Date, slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let runner = reminderDesk.runner()
        let outcome = await withBusy(L.t("rem_working")) { await runner.run(request) }
        guard outcome.changed || !Task.isCancelled else { return }
        flowMarkPersonal("ERINNERUNG \(request.stepWords) \(outcome.trace)")
        let model = settings.chatModel
        let artifacts = AnswerArtifacts(reminderRef: outcome.ref)
        finishAnswer(outcome.text, artifacts: artifacts, model: model, convID: convID,
                     started: started, slot: slot)
    }

    @MainActor func runTimerFlow(_ request: TimerRequest, convID: UUID, started: Date,
                                         slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let setting = await withBusy(L.t("timer_working")) { await timerDesk.setter.set(request) }
        guard setting.isSet || !Task.isCancelled else { return }
        flowMarkPersonal("TIMER \(request.stepWords) \(setting.trace)")
        let text = TimerAnswer.result(setting, request: request)
        let model = settings.chatModel
        finishAnswer(text, model: model, convID: convID, started: started, slot: slot)
    }

    @MainActor func runMusicFlow(_ request: MusicRequest, convID: UUID, started: Date,
                                         slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let runner = musicDesk.runner(preferred: settings.music.service)
        let outcome = await withBusy(L.t("music_working")) { await runner.run(request) }
        guard outcome.soundsNow || !Task.isCancelled else { return }
        musicDesk.remember(outcome)
        flowMarkPersonal("MUSIK \(request.stepWords) \(outcome.trace)")
        let model = settings.chatModel
        finishAnswer(outcome.text, model: model, convID: convID, started: started, slot: slot,
                     announce: !outcome.soundsNow)
    }

}
