@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import SwiftUI
import UIKit

@MainActor
final class ProbePhotoLibrary: PhotoLibraryAdding {
    var allowed = true
    var succeed = true
    private(set) var written = 0

    func allowsWriting() async -> Bool { allowed }

    func add(_ image: UIImage) async -> Bool {
        guard succeed else { return false }
        written += 1
        return true
    }
}

@MainActor
enum DebugGalleryProbe {
    static func run(_ view: ChatView) async {
        let started = ContinuousClock.now
        let report = SweepReport(file: "gallery_bar.txt")
        let files = makePictures(view.store.media)
        guard files.count == 5 else {
            report.add("AUFBAU", "fixtures fehlen: \(files.count)")
            return
        }
        let recorder = ProbePhotoLibrary()
        view.store.stand(in: PhotoLibraryWriter(library: recorder))
        defer { view.store.restorePhotos() }

        view.store.newConversation()
        guard let conv = view.store.current?.id, let message = seed(view, files: files, into: conv) else {
            report.add("AUFBAU", "keine unterhaltung")
            return
        }
        report.add("AUFBAU", "bilder=\(files.count) unterhaltung=\(conv)")

        await select(view, message: message, files: files, report: report, label: "AUSWAHL")
        await save(view, recorder: recorder, report: report)
        await denied(view, recorder: recorder, report: report)
        await failed(view, recorder: recorder, report: report)
        await cancel(view, report: report)
        await share(view, report: report)

        _ = view.store.removeConversation(conv)
        report.add("DAUER", "ms=\(msOf(started.duration(to: .now)))")
        flowLog.info("GALERIE fertig")
    }

    private static func makePictures(_ media: MediaStore) -> [String] {
        let names = (1...5).map { "img_probe_galerie_\($0).jpg" }
        for (index, name) in names.enumerated() where media.data(named: name) == nil {
            let side = CGSize(width: 320, height: 240)
            let image = UIGraphicsImageRenderer(size: side).image { context in
                UIColor(hue: CGFloat(index) / CGFloat(names.count), saturation: 0.72,
                        brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: side))
            }
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: media.paths.image(name))
            }
        }
        return names.filter { media.data(named: $0) != nil }
    }

    private static func seed(_ view: ChatView, files: [String], into conv: UUID) -> UUID? {
        let pictures = files.enumerated().map { index, file in
            WebPicture(file: file,
                       pageURL: "https://example.com/gallery/\(index)",
                       fullURL: "https://example.com/full/\(index).jpg",
                       title: "Probe \(index)",
                       domain: "example.com")
        }
        let gallery = PictureGallery(query: "probe", pictures: pictures, shown: pictures.count,
                                     nextOffset: 1, exhausted: true)
        view.store.appendAssistant(ChatView.galleryAnswer(gallery: gallery, failures: 0),
                                   model: "probe", elapsed: 1, to: conv,
                                   sources: gallery.chipSources.nilIfEmpty, gallery: gallery)
        return view.store.current?.messages.last?.id
    }

    private static func select(_ view: ChatView, message: UUID, files: [String],
                               report: SweepReport, label: String) async {
        let t0 = ContinuousClock.now
        view.gallerySelection.begin(owner: message)
        let picking = await ProbeWait.until(2) { view.gallerySelection.isPicking }
        view.gallerySelection.selectAll(files)
        let picked = await ProbeWait.until(2) {
            view.gallerySelection.count == files.count && view.showsGalleryBar
        }
        let plan = view.galleryBarPlan
        report.add(label, "begin=\(picking) alle=\(picked) gewaehlt=\(plan.selected)/\(plan.total) "
                   + "leiste=\(view.showsGalleryBar) titel=\(plan.saveTitle) "
                   + "mehr_alle=\(plan.showsSaveAll) ms=\(msOf(t0.duration(to: .now)))")
    }

    private static func save(_ view: ChatView, recorder: ProbePhotoLibrary, report: SweepReport) async {
        recorder.allowed = true
        recorder.succeed = true
        let before = recorder.written
        let t0 = ContinuousClock.now
        await view.saveGallerySelection()
        let done = await ProbeWait.until(3) { view.galleryOperation.result != nil }
        let seconds = msOf(t0.duration(to: .now))
        let result = view.galleryOperation.result
        let status = view.galleryBarPlan.statusLine
        report.add("SPEICHERN", "fertig=\(done) ergebnis=\(String(describing: result)) "
                   + "geschrieben=\(recorder.written - before) status=\(status) "
                   + "auswahl_weg=\(view.gallerySelection.isEmpty) ms=\(seconds)")
        view.galleryOperation.clearResult()
        view.gallerySelection.end()
    }

    private static func denied(_ view: ChatView, recorder: ProbePhotoLibrary, report: SweepReport) async {
        recorder.allowed = false
        guard let message = view.store.current?.messages.last?.id else { return }
        view.gallerySelection.begin(owner: message)
        let files = view.store.current?.messages.last?.gallery?.files ?? []
        view.gallerySelection.selectAll(files)
        await view.saveGallerySelection()
        let done = await ProbeWait.until(3) { view.galleryOperation.result == .denied }
        report.add("ABGELEHNT", "erreicht=\(done) status=\(view.galleryBarPlan.statusLine) "
                   + "auswahl_bleibt=\(!view.gallerySelection.isEmpty)")
        view.galleryOperation.clearResult()
        view.gallerySelection.end()
    }

    private static func failed(_ view: ChatView, recorder: ProbePhotoLibrary, report: SweepReport) async {
        recorder.allowed = true
        recorder.succeed = false
        guard let message = view.store.current?.messages.last?.id else { return }
        view.gallerySelection.begin(owner: message)
        let files = view.store.current?.messages.last?.gallery?.files ?? []
        view.gallerySelection.selectAll(files)
        await view.saveGallerySelection()
        let done = await ProbeWait.until(3) { view.galleryOperation.result == .failed }
        report.add("FEHLGESCHLAGEN", "erreicht=\(done) status=\(view.galleryBarPlan.statusLine) "
                   + "auswahl_bleibt=\(!view.gallerySelection.isEmpty)")
        recorder.succeed = true
        view.galleryOperation.clearResult()
        view.gallerySelection.end()
    }

    private static func cancel(_ view: ChatView, report: SweepReport) async {
        guard let message = view.store.current?.messages.last?.id else { return }
        view.gallerySelection.begin(owner: message)
        let files = view.store.current?.messages.last?.gallery?.files ?? []
        view.gallerySelection.selectAll(files)
        _ = await ProbeWait.until(2) { view.showsGalleryBar }
        let t0 = ContinuousClock.now
        view.cancelGallerySelection()
        let gone = await ProbeWait.until(2) { !view.showsGalleryBar && !view.gallerySelection.isPicking }
        report.add("ABBRECHEN", "leiste_weg=\(gone) ergebnis=\(String(describing: view.galleryOperation.result)) "
                   + "ms=\(msOf(t0.duration(to: .now)))")
    }

    private static func share(_ view: ChatView, report: SweepReport) async {
        guard let message = view.store.current?.messages.last?.id else { return }
        view.gallerySelection.begin(owner: message)
        let files = view.store.current?.messages.last?.gallery?.files ?? []
        view.gallerySelection.selectAll(files)
        let t0 = ContinuousClock.now
        view.shareGallerySelection()
        let sheet = await ProbeWait.until(4) { Presenter.topViewController is UIActivityViewController }
        let ended = view.gallerySelection.isEmpty
        report.add("TEILEN", "blatt=\(sheet) auswahl_weg=\(ended) ms=\(msOf(t0.duration(to: .now)))")
        Presenter.topViewController?.dismiss(animated: false)
        _ = await ProbeWait.until(3) { !(Presenter.topViewController is UIActivityViewController) }
    }
}
#endif
