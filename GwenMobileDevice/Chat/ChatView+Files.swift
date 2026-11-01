@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    func queue(pictures: [PendingPicture]) -> [PendingPicture] {
        let outcome = Self.keeping(pictures, alongside: pendingImages)
        pendingImages = outcome.kept
        guard outcome.dropped > 0 else { return pictures }
        queueAlert(L.FriendlyError(message: L.n("picture_limit", ImagePolicy.maxAttachmentsPerMessage),
                                   detail: L.n("picture_dropped", outcome.dropped),
                                   openSettings: false))
        return outcome.fresh
    }

    nonisolated static func keeping(_ added: [PendingPicture], alongside current: [PendingPicture])
        -> (kept: [PendingPicture], fresh: [PendingPicture], dropped: Int) {
        let merged = current + added
        let kept = Array(merged.prefix(ImagePolicy.maxAttachmentsPerMessage))
        let room = max(0, kept.count - current.count)
        return (kept, Array(added.prefix(room)), merged.count - kept.count)
    }

    func attachForEditing(_ att: Attachment) {
        let media = store.media
        let file = att.file
        Task {
            let t0 = ContinuousClock.now
            let decoded = try? await Offload.run { media.decodedDisplayImage(named: file) }
            guard let img = decoded else { return }
            flowMark("ATTACH_EDIT decode ms=\(msOf(t0.duration(to: .now))) size=\(Int(img.size.width))x\(Int(img.size.height))")
            let picture = PendingPicture(image: img, file: file)
            if let index = pendingImages.firstIndex(where: { $0.file == file }) {
                pendingImages[index] = picture
            } else {
                _ = queue(pictures: [picture])
            }
            inputFocused = true
        }
    }

    @MainActor func openFilePicker() {
        withAnimation(.easeInOut(duration: 0.15)) { attachMenu = false }
        DocumentPresenter.shared.present()
    }

    @MainActor func openVideoPicker() {
        withAnimation(.easeInOut(duration: 0.15)) { attachMenu = false }
        DocumentPresenter.shared.presentVideo()
    }

    @MainActor func importPicked(_ urls: [URL]) {
        withAnimation(.easeInOut(duration: 0.15)) { attachMenu = false }
        guard !urls.isEmpty else { return }
        Task { for url in urls { await importFile(url) } }
    }

    @MainActor func importFile(_ url: URL) async {
        guard let staged = await stageFile(url) else { return }
        let read = await readStagedFile(staged.pending, from: staged.url)
        guard read?.failed == true else { return }
        removePendingFile(staged.pending)
        queueAlert(L.FriendlyError(message: L.fmt("file_unreadable", staged.pending.name),
                                   detail: "", openSettings: false))
    }

    @MainActor func removePendingFile(_ pending: PendingFile) {
        pendingFiles.removeAll { $0.id == pending.id }
        store.documents.discardStored([pending.file])
    }

    @MainActor func stageFile(_ url: URL) async -> (pending: PendingFile, url: URL)? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        guard let kind = FileKind(filename: name) else {
            queueAlert(L.FriendlyError(message: L.t("file_unsupported"), detail: name, openSettings: false))
            return nil
        }
        guard pendingFiles.count < FilePolicy.maxFilesPerMessage else {
            queueAlert(L.FriendlyError(message: L.n("file_limit", FilePolicy.maxFilesPerMessage),
                                       detail: "", openSettings: false))
            return nil
        }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let bytes, bytes > FilePolicy.maxFileBytes {
            queueAlert(L.FriendlyError(message: L.fmt2("file_too_big", name,
                                                       StorageUsage.bytesText(FilePolicy.maxFileBytes)),
                                       detail: StorageUsage.bytesText(bytes), openSettings: false))
            return nil
        }
        let documents = store.documents
        let stored = await Offload.orNilFlat(priority: .utility) { documents.store(url: url) }
        guard let stored else {
            queueAlert(L.FriendlyError(message: L.t("file_import_failed"), detail: name, openSettings: false))
            return nil
        }
        guard stored.bytes <= FilePolicy.maxFileBytes else {
            documents.discardStored([stored.file])
            queueAlert(L.FriendlyError(message: L.fmt2("file_too_big", name,
                                                       StorageUsage.bytesText(FilePolicy.maxFileBytes)),
                                       detail: StorageUsage.bytesText(stored.bytes), openSettings: false))
            return nil
        }
        let pending = PendingFile(name: name, kind: kind, file: stored.file, bytes: stored.bytes)
        pendingFiles.append(pending)
        flowMarkPersonal("DATEI import name=\(name) art=\(kind.rawValue) bytes=\(stored.bytes)")
        return (pending, stored.url)
    }

    @MainActor func readStagedFile(_ pending: PendingFile, from url: URL) async -> PendingFile? {
        guard pending.kind != .video else {
            guard let index = pendingFiles.firstIndex(where: { $0.id == pending.id }) else { return nil }
            pendingFiles[index].reading = false
            pendingFiles[index].failed = false
            flowMarkPersonal("VIDEO import name=\(pending.name) bytes=\(pending.bytes)")
            return pendingFiles[index]
        }
        let kind = pending.kind
        let extracted = await withBusy(L.t("file_working")) {
            await Offload.orNil {
                DocumentExtractor.extract(url: url, kind: kind, ocrLanguages: TextRecognizing.languages)
            }
        }
        applyExtraction(extracted, toFile: pending.file, named: pending.name, id: pending.id)
        return pendingFiles.first { $0.id == pending.id }
    }

    @MainActor func acceptDroppedFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task { await analyzeDroppedFiles(urls) }
    }

    @MainActor func analyzeDroppedFiles(_ urls: [URL]) async {
        guard !dropRunning else { return }
        guard !isBusy, !isStreaming, !busy.isBusy else {
            queueAlert(L.FriendlyError(message: L.t("drop_busy"), detail: "", openSettings: false))
            return
        }
        guard settings.isConfigured else { showSettings = true; return }
        dropRunning = true
        defer { dropRunning = false }
        let draft = input
        let heldPictures = pendingImages
        let heldFiles = pendingFiles
        var pictures: [PendingPicture] = []
        var documents: [PendingFile] = []
        var unreadable: [String] = []
        for url in urls {
            switch DropPolicy.item(forFileNamed: url.lastPathComponent) {
            case .picture:
                if let picture = await importDroppedPicture(url) { pictures.append(picture) }
            case .document:
                guard let staged = await stageFile(url) else { continue }
                guard let read = await readStagedFile(staged.pending, from: staged.url), !read.failed else {
                    unreadable.append(staged.pending.name)
                    removePendingFile(staged.pending)
                    continue
                }
                documents.append(read)
            case nil:
                queueAlert(L.FriendlyError(message: L.t("file_unsupported"),
                                           detail: url.lastPathComponent, openSettings: false))
            }
        }
        for name in unreadable {
            queueAlert(L.FriendlyError(message: L.fmt("drop_no_text", name), detail: "",
                                       openSettings: false))
        }
        if pictures.count > ImagePolicy.maxAttachmentsPerMessage {
            queueAlert(L.FriendlyError(message: L.n("picture_limit", ImagePolicy.maxAttachmentsPerMessage),
                                       detail: L.n("picture_dropped",
                                                   pictures.count - ImagePolicy.maxAttachmentsPerMessage),
                                       openSettings: false))
            pictures = Array(pictures.prefix(ImagePolicy.maxAttachmentsPerMessage))
        }
        guard !pictures.isEmpty || !documents.isEmpty else {
            flowMark("DROP verworfen ohne lesbaren inhalt")
            return
        }
        let dropText = DropPrompt.text(pictures: pictures.count, files: documents.count)
        input = ""
        pendingFiles = []
        pendingImages = pictures
        input = dropText
        pendingFiles = documents
        flowMark("DROP analysieren bilder=\(pictures.count) dateien=\(documents.count) "
                 + "hinweis=\(TextLine.oneLine(input, limit: 80))")
        await sendNow()
        if input == dropText {
            pendingImages = Array((heldPictures + pendingImages).prefix(ImagePolicy.maxAttachmentsPerMessage))
            pendingFiles = Array((heldFiles + pendingFiles).prefix(FilePolicy.maxFilesPerMessage))
            if !draft.trimmed.isEmpty { input = draft + "\n\n" + dropText }
        }
        if input.isEmpty { input = draft }
        if pendingImages.isEmpty { pendingImages = heldPictures }
        if pendingFiles.isEmpty { pendingFiles = heldFiles }
    }

    @MainActor func importDroppedPicture(_ url: URL) async -> PendingPicture? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let maxPixel = ImagePolicy.uploadMaxPixel
        let loaded = await Offload.orNilFlat(priority: .utility) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return MediaStore.thumbnail(data, maxPixel: maxPixel)
        }
        guard let image = loaded else {
            queueAlert(L.FriendlyError(message: L.t("file_import_failed"),
                                       detail: url.lastPathComponent, openSettings: false))
            return nil
        }
        flowMark("DROP bild name=\(url.lastPathComponent) "
                 + "groesse=\(Int(image.size.width))x\(Int(image.size.height))")
        return PendingPicture(image: image, file: nil)
    }

    @MainActor func applyExtraction(_ extracted: ExtractedText?, toFile file: String,
                                    named name: String, id: UUID) {
        guard let index = pendingFiles.firstIndex(where: { $0.id == id }) else { return }
        pendingFiles[index].reading = false
        guard let extracted, extracted.chars > 0 else {
            pendingFiles[index].failed = true
            flowMarkPersonal("DATEI gelesen name=\(name) ohne verwertbaren text")
            return
        }
        pendingFiles[index].pages = extracted.pages
        pendingFiles[index].chars = extracted.chars
        pendingFiles[index].truncated = extracted.truncated
        pendingFiles[index].via = extracted.via
        store.documents.writeText(extracted.text, for: file)
        flowMarkPersonal("DATEI gelesen name=\(name) zeichen=\(extracted.chars) via=\(extracted.via.rawValue) "
                 + "seiten=\(extracted.pages.map(String.init) ?? "-")")
    }

    @MainActor func runOCR(on added: [PendingPicture]) {
        guard settings.autoOCR, !added.isEmpty else { return }
        let payloads = added.compactMap { picture -> (UUID, Data)? in
            guard let data = picture.image.jpegData(compressionQuality: 0.7) else { return nil }
            return (picture.id, data)
        }
        guard !payloads.isEmpty else { return }
        let ids = payloads.map(\.0)
        let datas = payloads.map(\.1)
        let languages = TextRecognizing.languages
        let stamp = Date()
        Task { @MainActor in
            let recognized: [(UUID, String)] = await Offload.orNil {
                var out: [(UUID, String)] = []
                for (index, data) in datas.enumerated() {
                    guard let text = TextRecognizing.recognize(data: data, languages: languages) else { continue }
                    out.append((ids[index], text))
                }
                return out
            } ?? []
            var remembered: [OcrFile] = []
            for (id, text) in recognized {
                let file = OcrTextStore.name(imageDate: stamp, suffix: String(id.uuidString.prefix(8)))
                OcrTextCache.shared.remember(text, for: file)
                let entry = OcrFile(file: file, chars: text.count)
                remembered.append(entry)
                if let position = pendingImages.firstIndex(where: { $0.id == id }) {
                    pendingImages[position].ocrFile = entry
                }
            }
            guard !remembered.isEmpty else { return }
            flowMark("OCR im_speicher=\(remembered.count) zeichen=\(remembered.reduce(0) { $0 + $1.chars })")
        }
    }

    nonisolated static func fileRefs(from history: [ChatMessage],
                                     carried: [String]?) -> [FileRef] {
        guard let lastUser = history.last(where: { $0.role == .user }) else { return [] }
        let readable = lastUser.files.filter(\.hasText)
        guard let carried else { return readable.map { FileRef($0) } }
        let names = Set(carried)
        return readable.filter { names.contains($0.name) }.map { FileRef($0) }
    }

}
