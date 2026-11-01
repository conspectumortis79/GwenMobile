@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func runWeatherFlow(_ request: WeatherRequest, convID: UUID, started: Date,
                                           slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        do {
            let service = weatherService
            let model = settings.chatModel
            let ref = try await busy.running(L.t("weather_working")) {
                try await service.day(for: request)
            }
            guard !Task.isCancelled else { return }
            let advice = WeatherAdviceRules.advice(for: ref)
            var text = WeatherAnswers.text(ref: ref, advice: advice)
            if let asked = request.place?.trimmed, !asked.isEmpty,
               !WeatherService.samePlace(asked, ref.place) {
                text = L.fmt("weather_place_found", ref.place) + " " + text
                flowMarkPersonal("WETTER ort korrigiert gefragt=\(asked) gefunden=\(ref.place)")
            }
            flowMarkPersonal("WETTER ort=\(ref.place) tag=\(ref.day) stunden=\(ref.hours.count) "
                             + "hinweise=\(advice.count)")
            finishAnswer(text, artifacts: AnswerArtifacts(weatherRef: ref), model: model,
                         convID: convID, started: started, slot: slot)
        } catch {
            guard !Task.isCancelled else { return }
            flowMarkPersonal("WETTER fehlgeschlagen grund=\(TextLine.oneLine(error.localizedDescription, limit: 120))")
            appendAnswerFailure(error, genericKey: "err_weather_generic", model: settings.chatModel,
                                convID: convID, started: started, slot: slot)
        }
    }

    @MainActor func switchWeatherDay(message: UUID, date: String) async {
        guard !Task.isCancelled else { return }
        guard let conversation = store.current,
              let current = conversation.messages.first(where: { $0.id == message }),
              let ref = current.weatherRef else { return }
        do {
            let service = weatherService
            let fresh = try await busy.running(L.t("weather_working")) {
                try await service.day(place: ref.placeValue, date: date)
            }
            guard !Task.isCancelled else { return }
            let text = WeatherAnswers.text(ref: fresh, advice: WeatherAdviceRules.advice(for: fresh))
            store.updateAssistantMessage(message, in: conversation.id) { updated in
                updated.text = text
                updated.model = settings.chatModel
                updated.weatherRef = fresh
            }
            flowMarkPersonal("WETTER tag=\(date) ort=\(fresh.place) datum=\(fresh.day)")
        } catch {
            guard !Task.isCancelled else { return }
            queueAlert(L.friendlyError(error.localizedDescription))
        }
    }

}
