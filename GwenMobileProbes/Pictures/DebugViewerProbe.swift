@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum ViewerProbe {
    struct Subject {
        let conversationID: UUID
        let messageID: UUID
        let files: [String]
        let tapped: String
    }

    static func subject(over conversations: [Conversation], media: MediaStore) -> Subject? {
        for conversation in conversations {
            for message in conversation.messages.reversed() {
                let stored = message.imageFiles.filter { media.storedURL(for: Attachment(file: $0)) != nil }
                guard let biggest = stored.max(by: { media.byteSize(of: $0) < media.byteSize(of: $1) }) else { continue }
                return Subject(conversationID: conversation.id, messageID: message.id,
                               files: stored, tapped: biggest)
            }
        }
        return nil
    }

    static func zoomScroll(in view: UIView, depth: Int = 0) -> ImageZoomScrollView? {        guard depth < 40 else { return nil }
        if let match = view as? ImageZoomScrollView { return match }
        for child in view.subviews {
            if let found = zoomScroll(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    static func waitUntilDismissed(limit: Int = 30) async -> Bool {
        for _ in 0..<limit {
            if Presenter.windowRootViewController?.presentedViewController == nil { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return Presenter.windowRootViewController?.presentedViewController == nil
    }

    static func storedPictures(in media: MediaStore, limit: Int) -> [String] {
        Array(media.fileNames().sorted().prefix(limit))
    }

    static func sheet(in scroll: ImageZoomScrollView) -> UIImageView? {
        scroll.delegate?.viewForZooming?(in: scroll) as? UIImageView
    }

    static func pager(in controller: UIViewController?) -> PagerHostController? {
        guard let controller else { return nil }
        if let match = controller as? PagerHostController { return match }
        for child in controller.children {
            if let found = pager(in: child) { return found }
        }
        return pager(in: controller.presentedViewController)
    }

    static func snapshot(_ window: UIWindow, named file: String, scale: CGFloat = 1) -> String {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let shot = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = shot.jpegData(compressionQuality: 0.62) else { return "fehlgeschlagen" }
        let url = StoragePaths().documents.appendingPathComponent(file)
        do {
            try data.write(to: url)
            return file
        } catch {
            return "schreiben_fehlgeschlagen"
        }
    }

    static func edge(_ image: UIImage) -> Int {
        Int(max(image.size.width, image.size.height) * image.scale)
    }

    static func text(_ value: CGFloat) -> String {
        String(format: "%.3f", value)
    }
}

extension ChatView {
    @MainActor func runViewerProbe() async {
        let report = SweepReport(file: "viewer_probe.txt")
        func note(_ section: String, _ detail: String) {
            report.add(section, detail)
        }
        note("marke", "viewerprobe-v7")
        guard let subject = ViewerProbe.subject(over: store.conversations, media: store.media) else {
            note("abbruch", "kein gespeichertes Chatbild im Verlauf")
            flowLog.error("VIEWERPROBE kein gespeichertes Bild")
            return
        }
        note("schritt", "subjekt gefunden")
        store.currentID = subject.conversationID
        try? await Task.sleep(for: .milliseconds(700))
        note("schritt", "unterhaltung gewechselt")
        scrollProxy?.scrollTo(ChatScrollAnchors.message(subject.messageID), anchor: .center)
        try? await Task.sleep(for: .milliseconds(1200))
        note("schritt", "zur nachricht gerollt")
        guard let window = Presenter.windowRootViewController?.view?.window else {
            note("abbruch", "kein Fenster")
            return
        }
        note("schritt", "fenster gefunden")
        note("tippen", "fingerdruck_laesst_sich_innen_nicht_synthetisieren=deckblaett_wird_unten_gesetzt")

        guard let preview = ImagePreviewTarget(tappedFile: subject.tapped, files: subject.files) else {
            note("abbruch", "ziel leer")
            return
        }
        imagePreview = preview
        _ = await ProbeWait.until(5) { ViewerProbe.zoomScroll(in: window) != nil }
        note("ziel", "datei=\(subject.tapped) bilder=\(subject.files.count) start=\(preview.startIndex) groesse=\(store.media.byteSize(of: subject.tapped))")
        note("deckblaett", "offen=\(imagePreview != nil)")

        guard let scroll = ViewerProbe.zoomScroll(in: window), let sheet = ViewerProbe.sheet(in: scroll),
              let picture = sheet.image else {
            note("zoomansicht", "nicht gefunden")
            note("screenshot", ViewerProbe.snapshot(window, named: "viewer_probe_keine_ansicht.jpg"))
            return
        }
        note("schritt", "zoomansicht gefunden")

        let expectedFit = ZoomGeometry.fitScale(container: scroll.bounds.size, image: picture.size)
        note("bild", "punkte=\(Int(picture.size.width))x\(Int(picture.size.height)) pxLangeKante=\(ViewerProbe.edge(picture)) kappeBetrachter=\(Int(ImagePolicy.viewerMaxPixel)) kappeBlase=\(Int(ImagePolicy.displayMaxPixel))")
        note("einpassmass", "min=\(ViewerProbe.text(scroll.minimumZoomScale)) max=\(ViewerProbe.text(scroll.maximumZoomScale)) aktuell=\(ViewerProbe.text(scroll.zoomScale)) erwartet=\(ViewerProbe.text(expectedFit))")
        note("rahmen", "blaetter=\(Int(scroll.bounds.width))x\(Int(scroll.bounds.height)) bild=\(Int(sheet.frame.width))x\(Int(sheet.frame.height)) fehlX=\(ViewerProbe.text(sheet.frame.minX - (scroll.bounds.width - sheet.frame.width) / 2)) fehlY=\(ViewerProbe.text(sheet.frame.minY - (scroll.bounds.height - sheet.frame.height) / 2))")

        let middle = CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY)
        let pager = ViewerProbe.pager(in: Presenter.windowRootViewController)
        scroll.handleDoubleTap(at: middle, animated: false)
        scroll.layoutIfNeeded()
        let detail = expectedFit * ZoomPolicy.viewer.detailFactor
        note("doppeltipp_hi", "aktuell=\(ViewerProbe.text(scroll.zoomScale)) erwartet=\(ViewerProbe.text(detail)) bild=\(Int(sheet.frame.width))x\(Int(sheet.frame.height))")
        note("blaettern_im_zoom", "wirt=\(pager != nil) zoomed=\(scroll.isZoomedIn) "
             + "erlaubt=\(pager?.isPagingEnabled ?? false)")
        note("screenshot_vergroessert", ViewerProbe.snapshot(window, named: "viewer_probe_zoom.jpg"))

        scroll.handleDoubleTap(at: middle, animated: false)
        scroll.layoutIfNeeded()
        note("doppeltipp_zurueck", "aktuell=\(ViewerProbe.text(scroll.zoomScale)) erwartet=\(ViewerProbe.text(expectedFit))")
        note("screenshot_eingepasst", ViewerProbe.snapshot(window, named: "viewer_probe_fit.jpg"))

        guard let pager else {
            note("blaettern", "wirt=nein")
            flowLog.info("VIEWERPROBE fertig datei=\(subject.tapped, privacy: .public)")
            return
        }
        note("blaettern_eingepasst", "zoomed=\(scroll.isZoomedIn) erlaubt=\(pager.isPagingEnabled) "
             + "sichtbar=\(pager.visibleIndex) von=\(subject.files.count)")
        let shown = pager.visibleIndex
        let neighbour = pager.pageAfter(shown)?.index ?? pager.pageBefore(shown)?.index ?? -1
        pager.turn(to: neighbour, animated: false)
        let arrived = pager.visibleIndex
        pager.turn(to: shown, animated: false)
        note("blaettern_probe", "nachbar=\(neighbour) blätterte=\(arrived == neighbour) "
             + "zurück=\(pager.visibleIndex == shown) nur_ein_bild=\(subject.files.count < 2)")
        await twoPictureTurn(report)
        flowLog.info("VIEWERPROBE fertig datei=\(subject.tapped, privacy: .public)")
    }

    @MainActor private func twoPictureTurn(_ report: SweepReport) async {
        let files = ViewerProbe.storedPictures(in: store.media, limit: 2)
        guard files.count == 2, ImagePreviewTarget(tappedFile: files[0], files: files) != nil else {
            report.add("ZWEI_BILDER", "keine_zwei_dateien")
            return
        }
        imagePreview = nil
        guard await ViewerProbe.waitUntilDismissed() else {
            report.add("ZWEI_BILDER", "erstes_deckblaett_ging_nicht_zu")
            return
        }
        imagePreview = ImagePreviewTarget(tappedFile: files[0], files: files)
        _ = await ProbeWait.until(5) { ViewerProbe.pager(in: Presenter.windowRootViewController) != nil }
        guard let pager = ViewerProbe.pager(in: Presenter.windowRootViewController),
              let window = Presenter.windowRootViewController?.view?.window,
              let first = ViewerProbe.zoomScroll(in: pager.view),
              let firstPicture = ViewerProbe.sheet(in: first)?.image else {
            report.add("ZWEI_BILDER", "wirt_oder_betrachter_fehlt")
            return
        }
        report.add("ZWEI_BILDER", "bilder=\(pager.pictureCount) sichtbar=\(pager.visibleIndex) "
                   + "erlaubt=\(pager.isPagingEnabled) "
                   + "erstes=\(Int(firstPicture.size.width))x\(Int(firstPicture.size.height)) "
                   + "nachbar=\(pager.pageAfter(0)?.index ?? -1)")
        let middle = CGPoint(x: first.bounds.midX, y: first.bounds.midY)
        first.handleDoubleTap(at: middle, animated: false)
        first.layoutIfNeeded()
        report.add("ZWEI_BILDER_IM_ZOOM", "zoomed=\(first.isZoomedIn) erlaubt=\(pager.isPagingEnabled)")
        first.handleDoubleTap(at: middle, animated: false)
        first.layoutIfNeeded()
        report.add("ZWEI_BILDER_BEI_FIT", "zoomed=\(first.isZoomedIn) erlaubt=\(pager.isPagingEnabled)")

        _ = await ProbeWait.until(5) { pager.page(at: 1) != .unavailable }
        report.add("zweite_seite_vorbereitet", "inhalt=\(pager.page(at: 1) == .unavailable ? "nichts" : "bild")")
        pager.turn(to: 1, animated: false)
        _ = await ProbeWait.until(5) { pager.visibleIndex == 1 }
        guard let scroll = ViewerProbe.zoomScroll(in: pager.view),
              let secondPicture = ViewerProbe.sheet(in: scroll)?.image else {
            report.add("ZWEI_BILDER_GEBLÄTTERT", "zweite_seite_zeigt_nichts")
            return
        }
        report.add("ZWEI_BILDER_GEBLÄTTERT", "sichtbar=\(pager.visibleIndex) "
                   + "erlaubt=\(pager.isPagingEnabled) "
                   + "zweites=\(Int(secondPicture.size.width))x\(Int(secondPicture.size.height)) "
                   + "anderes_bild=\(secondPicture !== firstPicture)")
        report.add("screenshot_zweites_bild", ViewerProbe.snapshot(window, named: "viewer_probe_zwei.jpg"))
        imagePreview = nil
    }
}
#endif
