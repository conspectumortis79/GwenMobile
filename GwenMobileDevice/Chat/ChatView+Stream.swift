@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func standaloneQuestion(_ question: String, history: [ChatMessage],
                                       picture: Data? = nil) async -> String {
        let raw = question.trimmed
        guard !raw.isEmpty else { return "" }
        guard history.count > 1 || picture != nil else { return raw }
        let model = settings.answeringModel(hasPictures: picture != nil)
        let query = try? await QwenAPI.resolveQuery(baseURL: settings.baseURL, key: settings.apiKey,
                                                    model: model, history: history, question: raw,
                                                    picture: picture,
                                                    thinking: settings.thinkingOffDirective(for: model))
        guard let query, FollowUpResolver.isUsable(query, insteadOf: raw) else {
            flowMarkPersonal("CTX keep frage=\(raw.prefix(60))")
            return raw
        }
        flowMarkPersonal("CTX rewrite frage=\(raw.prefix(40))\u{2192} frage=\(query.prefix(90))")
        return query
    }

    @MainActor func gatherWebHits(_ query: String, question: String, step: Int) async throws -> [WebHit] {
        markStatus(step, L.t("web_searching"))
        defer { markStatus(step, nil) }
        let region = Locale.current.region?.identifier.lowercased()
        let filterModel = settings.answeringModel(hasPictures: false)
        let research = WebResearch(onStatus: { status in markStatus(step, status) })
        func retrieve(_ term: String) async throws -> [WebHit] {
            try await research.hits(for: term) { term in
                try await WebSearch.searchURLs(term, region: region)
            }
        }
        func filter(_ hits: [WebHit]) async -> [WebHit] {
            markStatus(step, L.t("web_searching"))
            return await ToolRouter.keptSources(baseURL: settings.baseURL, key: settings.apiKey,
                                                model: filterModel, question: question, hits: hits,
                                                thinking: settings.thinkingOffDirective(for: filterModel)) { request in
                try await HTTP.jsonData(request)
            }
        }
        return try await WebSourceGathering.gather(query: query, question: question,
                                                   retrieve: retrieve, filter: filter,
                                                   onRetry: { markStatus(step, L.t("web_searching_question")) })
    }

    @MainActor func streamChat(turn: ModelTurn, history: [ChatMessage],
                               convID: UUID, started: Date, system: String? = nil,
                               question: String? = nil, focus: String = "",
                               query: String = "", memoryKeys: [String] = [],
                               slot: AnswerSlot? = nil) async {
        let model = settings.answeringModel(hasPictures: turn.needsVision, hasVideo: turn.needsVideo)
        let thinking = settings.thinkingDirective(for: model)
        let usedLevel = settings.activeThinkingLevel(for: model)
        let messages = turn.messages
        let images = turn.images
        let videos = turn.videos
        let baseURL = settings.baseURL
        let key = settings.apiKey
        let asked = question ?? history.last(where: { $0.role == .user })?.text ?? ""
        let baseSystem = (system ?? SystemPrompt.chat()) + (focus.isEmpty ? "" : "\n\n" + focus)
        let memoryBlock = query.isEmpty || memoryKeys.isEmpty
            ? "" : await store.memory.block(keys: memoryKeys)
        let combined = memoryBlock.isEmpty ? baseSystem : baseSystem + "\n\n" + memoryBlock
        let memoryRefs = settings.memory.chips && !memoryKeys.isEmpty
            ? await store.memory.entries(keys: memoryKeys).map(MemoryRef.init(entry:)) : []
        let artifacts = AnswerArtifacts(
            fileRefs: Self.fileRefs(from: history, carried: turn.carriedFileNames).nilIfEmpty,
            memoryRefs: memoryRefs.nilIfEmpty)

        do {
            let req = try await Offload.run { () throws -> URLRequest in
                try QwenAPI.makeRequest(baseURL: baseURL, key: key, model: model,
                                        messages: messages, imageData: images, videoData: videos,
                                        stream: true, system: combined, thinking: thinking)
            }
            flowMark("CHAT send msgs=\(messages.count) bilder=\(images.count) videos=\(videos.count) model=\(model)")
            let liveSpeech = slot == nil && speaksWhileAnswering
            var attempt = 1
            while true {
                let full = try await streamAnswer(req, liveSpeech: liveSpeech, step: slot?.step ?? 0)
                if Task.isCancelled {
                    finishCancelled(full, thinking: usedLevel, model: model, convID: convID,
                                    started: started, slot: slot)
                    return
                }
                let markers = ChatMarkers.parse(full)
                if markers.search {
                    let query = await withBusy(L.t("processing")) {
                        await self.standaloneQuestion(asked, history: history, picture: images.last)
                    }
                    await runWebSearch(query: query, question: asked, images: images,
                                       convID: convID, started: started, history: history,
                                       slot: slot)
                    return
                }
                if !full.trimmed.isEmpty {
                    await store.memory.markUsed(keys: memoryKeys)
                    finishAnswer(full, artifacts: artifacts, thinking: usedLevel, model: model,
                                 convID: convID, started: started, slot: slot)
                    return
                }
                guard attempt < 2 else {
                    appendFailure(AnswerError.marker + L.t("chat_answer_empty"), model: model,
                                  convID: convID, started: started, slot: slot)
                    return
                }
                attempt += 1
                flowMark("CHAT leer versuch=\(attempt)")
            }
        } catch let e as APIError {
            if RunStop.isCancellation(e) {
                finishCancelled(e.recoveredText, thinking: usedLevel, model: model, convID: convID,
                                started: started, slot: slot)
                return
            }
            let fe = L.friendlyError(e.message, model: model, status: e.status)
            if let r = e.recoveredText, !r.isEmpty {
                let broken = ChatMarkers.strip(r) + "\n\n\u{26a0}\u{fe0f} \(fe.message)"
                finishAnswer(broken, thinking: usedLevel, model: model, convID: convID,
                             started: started, slot: slot, announce: false)
            } else {
                reportChatFailure(e, model: model, convID: convID, started: started, slot: slot)
            }
        } catch {
            if RunStop.isCancellation(error) {
                finishCancelled(nil, thinking: usedLevel, model: model, convID: convID,
                                started: started, slot: slot)
                return
            }
            reportChatFailure(error, model: model, convID: convID, started: started, slot: slot)
        }
    }

    @MainActor func streamAnswer(_ req: URLRequest, liveSpeech: Bool = false,
                                 step: Int = 0) async throws -> String {
        let visible = streamLease.begin(step)
        isStreaming = streamLease.isBusy
        if visible { streamText = "" }
        if liveSpeech {
            speech.beginStream(voiceIdentifier: settings.voice.outputVoice)
            flowMark("VORLESEN strom start")
        }
        let throttle = StreamThrottle { chunk in if visible { streamText += chunk } }
        defer {
            if visible { streamText = "" }
            streamLease.end(step)
            isStreaming = streamLease.isBusy
            throttle.cancel()
            if liveSpeech { speech.endStream() }
            flowMark("VORLESEN strom ende")
        }
        return try await chatRunner(req, { chunk in
            throttle.receive(chunk)
            if liveSpeech { speech.stream(chunk) }
        })
    }

    @MainActor func markStatus(_ step: Int, _ label: String?) {
        if let label { statusLedger.show(label, for: step) } else { statusLedger.clear(step) }
        webStatus = statusLedger.text
    }

}
