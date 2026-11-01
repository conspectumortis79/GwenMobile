@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import UIKit

extension Bubble {
    func saveAsFile() {
        do {
            try Presenter.share(url: AnswerExporter().write(text: text, sources: sources, question: question,
                                                            model: model, elapsed: elapsed, time: time))
            notice.show(L.t("answers_saved"))
        } catch {
            shareFailure = error.localizedDescription
        }
    }

    @MainActor func scanShareView(_ file: AttachedFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(L.t("scan_share_head"))
            StoredFileCard(file: file, onOpen: { openFile(file) }, onShare: { shareScan(file) })
            Text(L.t("scan_saved_files"))
                .scaledFont(10)
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.horizontal, 4)
        }
    }

    @MainActor private func storedURL(for file: AttachedFile) -> URL? {
        guard let url = documents?.storedURL(for: file.file) else {
            notice.show(L.t("file_gone"))
            return nil
        }
        return url
    }

    @MainActor func shareScan(_ file: AttachedFile) {
        guard let url = storedURL(for: file) else { return }
        shareStored(url)
    }

    @MainActor func shareStored(_ url: URL?) {
        guard let url else { return }
        do {
            try Presenter.share(url: url)
        } catch {
            shareFailure = error.localizedDescription
        }
    }

    @MainActor var liveOCRFiles: [OcrFile] {
        ocrFiles.filter { OcrTextCache.shared.text(for: $0.file) != nil }
    }

    @MainActor var ocrFilesView: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            ForEach(liveOCRFiles, id: \.file) { entry in
                OcrFileCard(entry: entry) { openOCRFile(entry) }
            }
        }
    }

    @MainActor func openOCRFile(_ entry: OcrFile) {
        guard let text = OcrTextCache.shared.text(for: entry.file) else {
            notice.show(L.t("ocr_gone"))
            return
        }
        guard let url = OcrTextStore.temporaryFile(named: entry.file, text: text) else {
            notice.show(L.t("export_unavailable"))
            return
        }
        do {
            try Presenter.share(url: url)
        } catch {
            notice.show(L.t("export_unavailable"))
        }
    }

    var filesView: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            ForEach(files) { file in
                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    StoredFileCard(file: file) { openFile(file) }
                    if file.kind == .video {
                        Button(action: TapProbe.action({ saveVideo(file) })) {
                            Label(L.t("save_video"), systemImage: "square.and.arrow.down")
                                .scaledFont(12, weight: .semibold)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color(.secondaryLabel))
                        .accessibilityLabel(L.t("save_video"))
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
    }

    @MainActor func saveVideo(_ file: AttachedFile) {
        guard let url = storedURL(for: file) else { return }
        FileSavePresenter.shared.present(url: url, suggestedName: file.name) { saved in
            if saved { notice.show(L.t("video_saved")) }
        }
    }

    var fileRefsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fileRefsHeadingKey {
                sectionHeader(L.t(fileRefsHeadingKey))
            }
            OverflowChipRow(spacing: 6) {
                ForEach(Array(fileRefs.enumerated()), id: \.offset) { _, ref in
                    RefChip(symbol: "doc.text.fill", colour: Color(.secondaryLabel), text: ref.chipText)
                }
            }
        }
    }

    var extractionKey: String? {
        for ref in fileRefs {
            if let key = ref.privacyKey { return key }
        }
        return nil
    }

    @MainActor func openFile(_ file: AttachedFile) {
        guard let url = storedURL(for: file) else { return }
        QuickLookPresenter.shared.present(url: url, title: file.name)
    }

    func saveAttachment(_ att: Attachment) {
        saveAll([att])
    }

    func saveAllAttachments() {
        saveAll(outImages)
    }

    func saveAll(_ attachments: [Attachment]) {
        guard let media, !attachments.isEmpty else { return }
        let files = attachments.map(\.file)
        Task { @MainActor in
            let pictures = await Offload.orNil {
                files.compactMap { media.exportImage(named: $0) }
            } ?? []
            guard !pictures.isEmpty else {
                notice.show(L.t("image_gone"))
                return
            }
            notice.show(Self.savedLine(await photos.write(pictures)))
        }
    }

    nonisolated static func savedLine(_ outcome: PhotosWriteOutcome) -> String {
        switch outcome {
        case .saved(let count): return count > 1 ? L.n("pictures_saved_all", count) : L.t("image_saved")
        case .denied: return L.t("photos_not_allowed")
        case .failed: return L.t("save_failed")
        }
    }
}
