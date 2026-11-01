@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func runCalendarFlow(turn: ModelTurn, text: String, history: [ChatMessage],
                                            convID: UUID, started: Date,
                                            plan: QwenAPI.CalendarPlan? = nil, focus: String = "",
                                            slot: AnswerSlot? = nil, number: Int = 1) async {
        guard !Task.isCancelled else { return }
        await withBusy(L.t("cal_working")) {
            await self.calendarWork(turn: turn, text: text, history: history, convID: convID,
                                    started: started, plan: plan, focus: focus, slot: slot, number: number)
        }
    }

    @MainActor func calendarWork(turn: ModelTurn, text: String, history: [ChatMessage],
                                         convID: UUID, started: Date,
                                         plan: QwenAPI.CalendarPlan?, focus: String = "",
                                         slot: AnswerSlot? = nil, number: Int = 1) async {
        guard !Task.isCancelled else { return }
        let chatModel = settings.chatModel
        do {
            let resolved: QwenAPI.CalendarPlan?
            let already = slot?.carry.plannedText ?? ""
            if let plan, !plan.needsPlannerPass {
                flowMarkPersonal("KALENDER werkzeug-plan aktion=\(plan.action) titel=\(plan.title ?? "-")")
                resolved = plan
            } else {
                if let plan {
                    flowMarkPersonal("KALENDER werkzeug-plan nur geroutet aktion=\(plan.action) "
                                     + "titel=\(plan.title ?? "-") start=\(plan.start ?? "-") → nachplanung")
                }
                let planned = try await QwenAPI.calendarPlan(baseURL: settings.baseURL, key: settings.apiKey,
                                                              model: chatModel, instruction: text,
                                                              history: ConversationTranscript
                                                                .historyWithoutNewestQuestion(history),
                                                              events: CalendarService.upcomingContext(),
                                                              calendars: CalendarService.calendarsContext(),
                                                              planned: already,
                                                              thinking: settings.thinkingOffDirective(for: chatModel))
                guard !Task.isCancelled else { return }
                if let planned {
                    flowMarkPersonal("KALENDER planer aktion=\(planned.action) titel=\(planned.title ?? "-") "
                                     + "start=\(planned.start ?? "-") find=\(planned.find ?? "-")")
                }
                let words = planned?.lookupWords ?? plan?.lookupWords ?? ""
                let targetExists = (planned.map { CalendarService.matches($0) } ?? false)
                    || (slot?.carry.createdAppointment(named: words) ?? false)
                resolved = CalendarPlanRefiner.keepAction(plan, filledBy: planned,
                                                          targetExists: targetExists)
                if let plan, let resolved, plan.action == .create, resolved.action == .create,
                   plan.start != resolved.start || plan.title != resolved.title {
                    flowMarkPersonal("KALENDER nachgeplant aktion=create titel=\(resolved.title ?? "-") "
                                     + "start=\(resolved.start ?? "-")")
                }
            }
            guard !Task.isCancelled else { return }
            if let resolved, resolved.action != .none {
                if resolved.action == .create, slot?.carry.createdAlready(resolved) == true {
                    flowMarkPersonal("KALENDER doppelte Anlage übersprungen stufe=\(number) titel="
                                     + TextLine.oneLine(resolved.title ?? "-", limit: 40))
                    return
                }
                if number > 1, resolved.needsExistingEvent,
                   !CalendarService.matches(resolved),
                   !(slot?.carry.createdAppointment(named: resolved.lookupWords) ?? false) {
                    flowMarkPersonal("KALENDER geisterstufe übersprungen stufe=\(number) "
                                     + "aktion=\(resolved.action) suche="
                                     + TextLine.oneLine(resolved.lookupWords, limit: 40))
                    return
                }
                let outcome = try await CalendarService.perform(resolved)
                let chip = outcome.ref?.eventID ?? "-"
                flowMarkPersonal("KALENDER chip termin=\(chip) aktion=\(resolved.action)")
                if let slot {
                    slot.carry.notePlanned(outcome.notice, ref: outcome.ref)
                }
                finishAnswer(outcome.notice, artifacts: AnswerArtifacts(calendarRef: outcome.ref),
                             model: chatModel, convID: convID, started: started, slot: slot,
                             announce: false)
            } else if slot?.carry.hasPlannedAppointment == true {
                flowMark("KALENDER nichts übrig nach zweitem Durchgang → übersprungen")
            } else {
                await streamChat(turn: turn, history: history, convID: convID, started: started,
                                 question: text, focus: focus, slot: slot)
            }
        } catch {
            guard !Task.isCancelled else { return }
            appendAnswerFailure(error, genericKey: "err_cal_generic", model: chatModel,
                                convID: convID, started: started, slot: slot)
        }
    }

}
