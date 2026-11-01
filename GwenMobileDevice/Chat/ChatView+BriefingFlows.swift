@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func runDayBriefingFlow(_ request: DayBriefingRequest, convID: UUID, started: Date,
                                                slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let service = briefingDesk.service(includes: settings.briefing.includes)
        let ref = await withBusy(L.t("brief_working")) { await service.build(request.day) }
        guard !Task.isCancelled else { return }
        let text = DayBriefingAnswers.text(ref)
        flowMarkPersonal("BRIEFING tag=\(request.day.rawValue) termine=\(ref.events.count) "
                         + "offen=\(ref.reminders.count) geburtstage=\(ref.birthdays.count) "
                         + "wetter=\(ref.weather != nil) fahrzeit=\(ref.travel?.hasTimes ?? false)")
        finishAnswer(text, artifacts: AnswerArtifacts(dayBriefingRef: ref), model: settings.chatModel,
                     convID: convID, started: started, slot: slot)
    }

    @MainActor func switchBriefingDay(message: UUID, day: String) async {
        guard !Task.isCancelled else { return }
        guard let conversation = store.current,
              let current = conversation.messages.first(where: { $0.id == message }),
              current.dayBriefingRef != nil,
              let requested = BriefingDay(rawValue: day) else { return }
        let service = briefingDesk.service(includes: settings.briefing.includes)
        let ref = await withBusy(L.t("brief_working")) { await service.build(requested) }
        guard !Task.isCancelled else { return }
        store.updateAssistantMessage(message, in: conversation.id) { updated in
            updated.text = DayBriefingAnswers.text(ref)
            updated.model = settings.chatModel
            updated.dayBriefingRef = ref
        }
        flowMarkPersonal("BRIEFING tag=\(requested.rawValue) termine=\(ref.events.count) "
                         + "offen=\(ref.reminders.count)")
    }

    @MainActor func speakBriefing(message: UUID) {
        guard let text = store.current?.messages.first(where: { $0.id == message })?.text,
              !text.isEmpty else { return }
        flowMarkPersonal("BRIEFING vorlesen zeichen=\(text.count)")
        speech.speak(text: text, voiceIdentifier: settings.voice.outputVoice)
    }

    @MainActor func notifyBriefing(message: UUID) {
        guard let ref = store.current?.messages.first(where: { $0.id == message })?.dayBriefingRef else {
            return
        }
        DayBriefingNotifier.preparePermission()
        DayBriefingNotifier.post(ref)
        flowMarkPersonal("BRIEFING mitteilung sofort tag=\(ref.date)")
    }

    @MainActor func takeBriefingOpenRequest() {
        guard briefingOpens.token > handledBriefingOpen else { return }
        handledBriefingOpen = briefingOpens.token
        briefingOpenDay = briefingOpens.day
        showBriefingOpen = true
        flowMark("BRIEFING öffnen token=\(briefingOpens.token) tag=\(briefingOpenDay.rawValue) "
                 + "sheet=\(showBriefingOpen)")
    }

}
