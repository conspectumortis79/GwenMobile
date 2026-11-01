@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func imagePrompt(_ text: String, history: [ChatMessage],
                                        pictures: Int) async -> String {
        guard pictures > 1 || history.contains(where: { $0.role == .assistant }) else {
            return text
        }
        let composed = try? await QwenAPI.composeImagePrompt(baseURL: settings.baseURL, key: settings.apiKey,
                                                             model: settings.chatModel,
                                                             instruction: text, history: history,
                                                             pictures: pictures,
                                                             thinking: settings.thinkingOffDirective(for: settings.chatModel))
        guard let composed else { return text }
        flowMarkPersonal("CTX bild frage=\(text.prefix(40))\u{2192} prompt=\(composed.prefix(90))")
        return composed
    }

    @MainActor func runImageFlow(prompt: String, history: [ChatMessage], turn: ModelTurn,
                                         fresh: [String], isEdit: Bool, convID: UUID, started: Date,
                                         composeFromChat: Bool = true, monochrome: Bool = false,
                                         slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        guard settings.hasImageModel else {
            appendFailure(L.t("no_image_model"), model: nil, convID: convID, started: started, slot: slot)
            return
        }
        await withBusy(BusyOverlay.pictureLabel(editing: isEdit)) {
            await self.imageWork(prompt: prompt, history: history, turn: turn, fresh: fresh,
                                 isEdit: isEdit, monochrome: monochrome, convID: convID, started: started,
                                 composeFromChat: composeFromChat, slot: slot)
        }
    }

    @MainActor func imageWork(prompt: String, history: [ChatMessage], turn: ModelTurn,
                                      fresh: [String], isEdit: Bool, monochrome: Bool, convID: UUID,
                                      started: Date, composeFromChat: Bool, slot: AnswerSlot?) async {
        guard !Task.isCancelled else { return }
        let baseURL = settings.baseURL
        let key = settings.apiKey
        let imageModel = settings.imageModel
        let images = turn.images
        let instruction = prompt.isEmpty ? L.t("image_default_prompt") : prompt
        let directingModel = settings.answeringModel(hasPictures: !images.isEmpty)
        let directed = isEdit && images.count > 1
            ? await PictureDirector.observe(baseURL: baseURL, key: key, model: directingModel,
                                            instruction: instruction, pictures: images,
                                            fresh: turn.positions(of: fresh),
                                            thinking: settings.thinkingOffDirective(for: directingModel))
            : nil
        guard !Task.isCancelled else { return }
        if directed == .unreachable {
            let notice = Self.unreachablePictureNotice(leftBehind: turn.picturesLeftBehind)
            finishAnswer(notice, model: imageModel, convID: convID, started: started, slot: slot,
                         announce: false)
            return
        }
        let pictures = directed?.pictures(from: images) ?? images
        if isEdit, monochrome, let first = pictures.first, let edited = ImageDelivery.monochrome(first),
           let name = store.media.storeImageData(edited) {
            guard !Task.isCancelled else { return }
            flowMark("IMAGEFLOW lokal schwarzweiss bilder=1")
            finishAnswer(L.t("edit_done_note"), artifacts: AnswerArtifacts(outImages: [Attachment(file: name)]),
                         model: imageModel, convID: convID, started: started, slot: slot, announce: false,
                         preview: true)
            return
        }
        let text: String
        if case .edit(_, _, let rewritten)? = directed {
            text = rewritten
        } else if isEdit {
            text = instruction
        } else if composeFromChat {
            text = await imagePrompt(instruction, history: history, pictures: images.count)
        } else {
            text = instruction
        }
        guard !Task.isCancelled else { return }
        flowMark("IMAGEFLOW start edit=\(isEdit) bilder=\(pictures.count) \(directed?.trace ?? "ohne regie")")
        flowMarkPersonal("IMAGEFLOW prompt=\(text.prefix(60))")
        guard let backend = settings.descriptor.imageBackend else { return }
        let delivery = ImageDelivery(media: store.media, backend: backend)
        do {
            let outAtts = try await delivery.makePicture(baseURL: baseURL, key: key, model: imageModel,
                                                         prompt: text, inputImages: pictures, isEdit: isEdit)
            guard !Task.isCancelled else { return }
            flowMark("IMAGEFLOW generated pictures=\(outAtts.count)")
            let note = isEdit ? L.t("edit_done_note") : ""
            finishAnswer(note, artifacts: AnswerArtifacts(outImages: outAtts), model: imageModel,
                         convID: convID, started: started, slot: slot, announce: false, preview: true)
        } catch {
            flowMark("IMAGEFLOW fehler abbruch=\(Task.isCancelled) art=\(type(of: error)) "
                     + TextLine.oneLine(error.localizedDescription, limit: 120))
            if isEdit, monochrome, let first = pictures.first,
               let raw = (error as? APIError)?.message ?? error.localizedDescription as String?,
               IntentHeuristics.safetyRejection.matches(raw.lowercased()),
               let edited = ImageDelivery.monochrome(first),
               let outAtts = try? await delivery.store([.inline(edited)]) {
                guard !Task.isCancelled else { return }
                flowMark("IMAGEFLOW lokal schwarzweiss bilder=\(outAtts.count) grund=\(raw.prefix(60))")
                finishAnswer(L.t("edit_done_note"), artifacts: AnswerArtifacts(outImages: outAtts),
                             model: imageModel, convID: convID, started: started, slot: slot, announce: false,
                             preview: true)
                return
            }
            appendModelFailure(error, model: imageModel, convID: convID, started: started, slot: slot)
        }
    }

    nonisolated static func unreachablePictureNotice(leftBehind: Int) -> String {
        leftBehind > 0
            ? L.fmt2("picture_out_of_memory", String(leftBehind), String(ConversationMemory.maxPictures))
            : L.t("picture_nothing_matches")
    }

    @MainActor func runPictureSearch(query: String, images: [Data],
                                             convID: UUID, started: Date, history: [ChatMessage],
                                             slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        let chatModel = settings.chatModel
        do {
            let round = try await searchPictures(query: query, offset: 1, step: slot?.step ?? 0)
            guard !Task.isCancelled else { return }
            let gallery = PictureGallery(query: query, pictures: round.pictures,
                                         shown: ImagePolicy.galleryInitialItems,
                                         nextOffset: round.nextOffset, exhausted: round.exhausted)
            let answer = Self.galleryAnswer(gallery: gallery, failures: round.failures)
            flowMark("BILDERSUCHE query=\(query.prefix(40)) treffer=\(round.pictures.count) "
                     + "fehlgeschlagen=\(round.failures) weiter=\(round.nextOffset) erschöpft=\(round.exhausted)")
            finishAnswer(answer, artifacts: AnswerArtifacts(sources: gallery.chipSources.nilIfEmpty,
                                                            gallery: gallery),
                         model: chatModel, convID: convID, started: started, slot: slot)
        } catch {
            guard !Task.isCancelled else { return }
            flowMark("BILDERSUCHE leer → websuche begründung=\(error.localizedDescription.prefix(40))")
            await runWebSearch(query: query, images: images, convID: convID,
                               started: started, history: history, slot: slot)
        }
    }

    @MainActor func searchPictures(query: String, offset: Int, step: Int) async throws -> PictureRound {
        let flow = PictureSearchFlow(media: store.media) { status in markStatus(step, status) }
        markStatus(step, L.t("pictures_searching"))
        defer { markStatus(step, nil) }
        return try await flow.run(query: query, offset: offset)
    }

    @MainActor func morePictures(_ message: ChatMessage) async {
        guard !Task.isCancelled else { return }
        guard let gallery = message.gallery, let convID = store.currentID else { return }
        if gallery.hiddenCount > 0 {
            store.updateGallery(message.id, in: convID, gallery.revealingMore())
            return
        }
        guard !gallery.exhausted else {
            queueAlert(L.FriendlyError(message: L.t("pictures_no_more"), detail: gallery.query,
                                       openSettings: false))
            return
        }
        webStatus = L.t("pictures_more_working")
        galleryOperation.beginSearch(message.id)
        defer { galleryOperation.endSearch(message.id) }
        do {
            let round = try await searchPictures(query: gallery.query, offset: gallery.nextOffset, step: 0)
            guard !Task.isCancelled else { return }
            store.updateGallery(message.id, in: convID, gallery.merging(round))
        } catch {
            guard !Task.isCancelled else { return }
            queueAlert(L.friendlyError(error.localizedDescription))
        }
        webStatus = nil
    }

    var selectedGallery: PictureGallery? {
        guard let owner = gallerySelection.owner else { return nil }
        return store.current?.messages.first { $0.id == owner }?.gallery
    }

    var showsGalleryBar: Bool {
        galleryOperation.showsBar || (gallerySelection.isPicking && !gallerySelection.isEmpty)
    }

    var galleryBarPlan: GalleryBarPlan {
        GalleryBarPlan.make(selected: gallerySelection.count,
                            total: selectedGallery?.pictures.count ?? 0,
                            progress: galleryOperation.saving,
                            result: galleryOperation.result)
    }

    @ViewBuilder var galleryBar: some View {
        if showsGalleryBar {
            GalleryActionBar(plan: galleryBarPlan,
                             onSave: { Task { await saveGallerySelection() } },
                             onShare: { shareGallerySelection() },
                             onSaveAll: { Task { await saveWholeGallery() } },
                             onCancel: { cancelGallerySelection() })
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @MainActor func saveGallerySelection() async {
        await writeGalleryPictures(gallerySelection.pictures(in: selectedGallery))
    }

    @MainActor func saveWholeGallery() async {
        await writeGalleryPictures(selectedGallery?.pictures ?? [])
    }

    @MainActor func writeGalleryPictures(_ pictures: [WebPicture]) async {
        let files = pictures.map(\.file)
        guard !files.isEmpty else { return }
        let media = store.media
        let images = await Offload.orNil { files.compactMap { media.exportImage(named: $0) } } ?? []
        guard !Task.isCancelled else { return }
        guard !images.isEmpty else {
            galleryOperation.finishSaving(.failed)
            return
        }
        galleryOperation.beginSaving(total: images.count)
        let writer = store.photos
        let outcome = await writer.write(images) { _ in galleryOperation.advanceSaving() }
        galleryOperation.finishSaving(outcome)
        if outcome.didWrite { gallerySelection.end() }
    }

    @MainActor func shareGallerySelection() {
        let pool = gallerySelection.isEmpty ? (selectedGallery?.pictures ?? [])
            : gallerySelection.pictures(in: selectedGallery)
        let urls = pool.compactMap { store.media.storedURL(for: $0.attachment) }
        guard !urls.isEmpty else {
            queueAlert(L.FriendlyError(message: L.t("image_gone"), detail: "", openSettings: false))
            return
        }
        do {
            try Presenter.share(urls: urls)
            gallerySelection.end()
        } catch {
            queueAlert(L.FriendlyError(message: error.localizedDescription, detail: "",
                                       openSettings: false))
        }
    }

    @MainActor func cancelGallerySelection() {
        galleryOperation.clearResult()
        gallerySelection.end()
    }

    nonisolated static func galleryAnswer(gallery: PictureGallery, failures: Int) -> String {
        var answer = L.fmt2("pictures_answer", String(gallery.pictures.count), gallery.query)
        if failures > 0 {
            answer += "\n" + L.fmt2("pictures_partial", String(gallery.pictures.count),
                                    String(gallery.pictures.count + failures))
        }
        return answer
    }

}
