@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func runWebSearch(query: String, question: String? = nil, images: [Data],
                                 convID: UUID, started: Date,
                                 history: [ChatMessage], slot: AnswerSlot? = nil,
                                 detailWish: Bool = false) async {
        guard !Task.isCancelled else { return }
        let webStarted = ContinuousClock.now
        let pictures = settings.provider == .local ? [] : images
        let asked = question?.trimmed.nilIfEmpty ?? query
        let answerModel = settings.answeringModel(hasPictures: !pictures.isEmpty)
        let thinking = settings.thinkingDirective(for: answerModel)
        let usedLevel = settings.activeThinkingLevel(for: answerModel)
        do {
            let hits = try await gatherWebHits(query, question: asked, step: slot?.step ?? 0)
            guard !Task.isCancelled else { return }
            guard !hits.isEmpty else { throw APIError(message: L.t("web_no_results")) }
            let researchBaseURL = settings.baseURL
            let researchKey = settings.apiKey
            let length = AnswerLengthPlan.fitting(history, detailWish: detailWish)
            let req = try await Offload.run {
                try WebSearch.makeAnswerRequest(baseURL: researchBaseURL, key: researchKey,
                                                model: answerModel, question: asked, hits: hits,
                                                history: history, images: pictures,
                                                length: length, thinking: thinking)
            }
            let streamStarted = ContinuousClock.now
            let liveSpeech = slot == nil && speaksWhileAnswering
            let streamed = try await streamAnswer(req, liveSpeech: liveSpeech, step: slot?.step ?? 0)
            guard !Task.isCancelled else { return }
            let markers = ChatMarkers.parse(streamed)
            flowMark("WEBANTWORT zeichen=\(streamed.count) such_token=\(markers.search) \(length.traceLine) "
                     + "dauer_ms=\(msOf(streamStarted.duration(to: .now)))")
            let answer = ChatMarkers.strip(streamed)
            guard !answer.isEmpty else { throw APIError(message: L.t("web_no_answer")) }
            let sources = WebResearch.sources(from: hits)
            let artifacts = AnswerArtifacts(sources: sources)
            flowMark("WEBENDE dauer_ms=\(msOf(webStarted.duration(to: .now))) quellen=\(hits.count)")
            let placement = finishAnswer(answer, artifacts: artifacts, thinking: usedLevel, model: answerModel,
                                         convID: convID, started: started, slot: slot)
            if settings.research.verifySources {
                startSourceCheck(answer: answer, hits: hits, model: answerModel, placement: placement)
            }
        } catch {
            guard !Task.isCancelled else { return }
            appendAnswerFailure(error, genericKey: "err_web_generic", model: answerModel,
                                convID: convID, started: started, slot: slot)
        }
    }

    @MainActor func startSourceCheck(answer: String, hits: [WebHit], model: String,
                                     placement: AnswerPlacement?) {
        guard let placement else { return }
        Task { @MainActor in
            guard let messageID = await placement.resolvedMessageID() else {
                flowMark("PRUEFUNG verworfen grund=keine antwort")
                return
            }
            sourceChecks.insert(messageID)
            flowMark("PRUEFUNG gestartet nachricht=\(messageID.uuidString.prefix(8)) quellen=\(hits.count) "
                     + "antwort_sichtbar=true")
            let review = await reviewSources(answer, hits: hits, model: model)
            sourceChecks.remove(messageID)
            let applied = placement.applySourceReview(review, to: store)
            flowMark("PRUEFUNG fertig nachricht=\(messageID.uuidString.prefix(8)) eingetragen=\(applied) "
                     + "verifiziert=\(review.verified) geprueft=\(review.checkedClaims) "
                     + "unbelegt=\(review.unsupported.count) widersprochen=\(review.contradicted.count)")
        }
    }

    @MainActor func reviewSources(_ answer: String, hits: [WebHit], model: String) async -> SourceReview {
        var review = await Offload.value { SourceReview.analyze(answer: answer, hits: hits) }
        guard review.citedClaims > 0 else { return review }
        let verifier = SourceVerifier(baseURL: settings.baseURL, key: settings.apiKey, model: model,
                                      thinking: settings.thinkingOffDirective(for: model))
        let verifyStarted = ContinuousClock.now
        review = await verifier.apply(to: review, answer: answer, hits: hits)
        flowMark("QUELLENPRUEFUNG quellen=\(hits.count) zitate=\(review.citedClaims) "
                 + "geprueft=\(review.checkedClaims) unbelegt=\(review.unsupported.count) "
                 + "einzelquelle=\(review.singleSource) dauer_ms=\(msOf(verifyStarted.duration(to: .now)))")
        return review
    }

}
