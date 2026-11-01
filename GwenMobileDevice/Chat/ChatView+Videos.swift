@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import AVFoundation
import SwiftUI

extension ChatView {
    @MainActor func runVideoFlow(_ request: VideoRequest, sourceVideo: Data? = nil,
                                 sourceFile: String? = nil, convID: UUID, started: Date,
                                 slot: AnswerSlot? = nil) async {
        guard !Task.isCancelled else { return }
        guard settings.hasVideoGenerationModel,
              let backend = settings.descriptor.videoGenerationBackend else {
            appendFailure(L.t("no_video_generation_model"), model: nil, convID: convID,
                          started: started, slot: slot)
            return
        }
        let model = settings.videoGenerationModel
        var effective = request
        if let sourceFile, let seconds = await sourceSeconds(sourceFile) {
            effective.duration = min(max(seconds, VideoRequest.minimumDuration),
                                     VideoRequest.maximumDuration)
        }
        await withBusy(L.t("video_working")) {
            await self.videoWork(effective, sourceVideo: sourceVideo, backend: backend, model: model,
                                 convID: convID, started: started, slot: slot)
        }
    }

    @MainActor private func sourceSeconds(_ file: String) async -> Int? {
        guard let url = store.documents.storedURL(for: file) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return nil }
        return Int(seconds.rounded())
    }

    @MainActor private func videoWork(_ request: VideoRequest, sourceVideo: Data?,
                                      backend: any VideoGenerating, model: String, convID: UUID,
                                      started: Date, slot: AnswerSlot?) async {
        let baseURL = settings.baseURL
        let key = settings.apiKey
        flowMarkPersonal("VIDEO start model=\(model) dauer=\(request.clampedDuration)s "
                         + "format=\(request.ratio.rawValue) quelle=\(sourceVideo?.count ?? 0) "
                         + "prompt=\(request.prompt.prefix(80))")
        do {
            let generated = try await backend.generate(baseURL: baseURL, key: key, model: model,
                                                       request: request, sourceVideo: sourceVideo)
            try Task.checkCancellation()
            guard generated.data.count <= VideoPolicy.maxBytes else {
                throw APIError(message: L.t("video_download_failed"))
            }
            let documents = store.documents
            let name = "GwenMobile-Video-\(Int(Date().timeIntervalSince1970))."
                + generated.fileExtension
            guard let stored = await Offload.orNilFlat(priority: .utility, {
                documents.store(data: generated.data, fileExtension: generated.fileExtension)
            }) else {
                throw APIError(message: L.t("video_generation_failed"))
            }
            let file = AttachedFile(file: stored.file, name: name, kind: .video, bytes: stored.bytes)
            flowMarkPersonal("VIDEO gespeichert datei=\(stored.file) bytes=\(stored.bytes)")
            finishAnswer(L.t("video_done_note"), artifacts: AnswerArtifacts(files: [file]),
                         model: model, convID: convID, started: started, slot: slot,
                         announce: false)
        } catch {
            flowMarkPersonal("VIDEO fehler abbruch=\(Task.isCancelled) "
                             + TextLine.oneLine(error.localizedDescription, limit: 120))
            guard !Task.isCancelled else { return }
            appendAnswerFailure(error, genericKey: "video_generation_failed", model: model,
                                convID: convID, started: started, slot: slot)
        }
    }
}
