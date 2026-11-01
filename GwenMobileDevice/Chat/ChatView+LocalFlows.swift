@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func runTranslationFlow(_ job: TranslationJob, convID: UUID, started: Date,
                                              slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let effective = slot.map { job.resolved(with: $0.carry) } ?? job
        let credentials = TranslationCredentials(baseURL: settings.baseURL, apiKey: settings.apiKey,
                                                model: settings.chatModel,
                                                thinking: settings.thinkingOffDirective(for: settings.chatModel))
        do {
            let done = try await busy.running(TranslationFlow.busyLabel(for: effective)) {
                try await TranslationFlow.run(effective, credentials: credentials)
            }
            guard !Task.isCancelled else { return }
            flowMarkPersonal("ÜBERSETZUNG ergebnis gerät=\(done.onDevice) \(effective.trace) "
                             + "ziel=\(effective.targetCode) ms=\(Int(Date().timeIntervalSince(started) * 1000))")
            finishAnswer(done.text, model: done.signature, convID: convID, started: started, slot: slot)
        } catch let problem as TranslationProblem {
            guard !Task.isCancelled else { return }
            flowMarkPersonal("ÜBERSETZUNG fehl geschlagen \(job.trace) ziel=\(job.targetCode)")
            queueAlert(problem.alert)
        } catch {
            guard !Task.isCancelled else { return }
            flowMarkPersonal("ÜBERSETZUNG abbruch \(job.trace) ziel=\(job.targetCode)")
            queueAlert(L.friendlyError(error.localizedDescription))
        }
    }

    @MainActor func runPlaceFlow(_ kind: PlaceFlowRunner.Kind, terms: [String], wish: String,
                                         mode: TravelMode, convID: UUID, started: Date,
                                         slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let runner = PlaceFlowRunner(search: placeSearch, model: settings.chatModel)
        let outcome = await withBusy(L.t(kind.copy.busyKey)) {
            await runner.run(kind, terms: terms, wish: wish, mode: mode)
        }
        guard !Task.isCancelled else { return }
        routeDesk.record(outcome.hits)
        let groups = PlaceGroup.single(outcome.places, headingKey: outcome.headingKey)
        finishAnswer(outcome.text, artifacts: AnswerArtifacts(placeGroups: groups),
                     model: settings.chatModel, convID: convID, started: started, slot: slot)
    }

    @MainActor func tellTime(_ request: ClockRequest, convID: UUID, started: Date,
                                     slot: AnswerSlot? = nil) {
        let text = ClockAnswer.text(now: Date(), request: request)
        flowMarkPersonal("UHRZEIT zone=\(request.timeZone ?? "hier") ort=\(request.place ?? "-")")
        let model = settings.chatModel
        finishAnswer(text, model: model, convID: convID, started: started, slot: slot)
    }

    @MainActor func openRoute(to place: NearbyPlace) {
        let handedOff = routeDesk.openRoute(for: place)
        flowMarkPersonal("ROUTE übergabe=\(handedOff) modus=\(place.mode.rawValue) ziel=\(place.name)")
        guard !handedOff else { return }
        queueAlert(L.FriendlyError(message: L.t("route_handoff_failed"), detail: place.name,
                                   openSettings: false))
    }

}
