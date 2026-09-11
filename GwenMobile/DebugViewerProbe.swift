#if DEBUG
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

    static func zoomScroll(in view: UIView, depth: Int = 0) -> ImageZoomScrollView? {
        guard depth < 40 else { return nil }
        if let match = view as? ImageZoomScrollView { return match }
        for child in view.subviews {
            if let found = zoomScroll(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    static func sheet(in scroll: ImageZoomScrollView) -> UIImageView? {
        scroll.delegate?.viewForZooming?(in: scroll) as? UIImageView
    }

    static func snapshot(_ window: UIWindow, named file: String) -> String {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
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
        var report = SweepReport()
        func note(_ section: String, _ detail: String) {
            report.add(section, detail)
            report.write(into: "viewer_probe.txt")
        }
        note("marke", "viewerprobe-v6")
        guard let subject = ViewerProbe.subject(over: store.conversations, media: store.media) else {
            note("abbruch", "kein gespeichertes Chatbild im Verlauf")
            flowLog.error("VIEWERPROBE kein gespeichertes Bild")
            return
        }
        note("schritt", "subjekt gefunden")
        store.currentID = subject.conversationID
        try? await Task.sleep(for: .milliseconds(700))
        note("schritt", "unterhaltung gewechselt")
        scrollProxy?.scrollTo("msg-\(subject.messageID.uuidString)", anchor: .center)
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
        try? await Task.sleep(for: .milliseconds(1700))
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
        scroll.handleDoubleTap(at: middle, animated: false)
        scroll.layoutIfNeeded()
        let detail = expectedFit * ZoomPolicy.viewer.detailFactor
        note("doppeltipp_hi", "aktuell=\(ViewerProbe.text(scroll.zoomScale)) erwartet=\(ViewerProbe.text(detail)) bild=\(Int(sheet.frame.width))x\(Int(sheet.frame.height))")
        note("screenshot_vergroessert", ViewerProbe.snapshot(window, named: "viewer_probe_zoom.jpg"))

        scroll.handleDoubleTap(at: middle, animated: false)
        scroll.layoutIfNeeded()
        note("doppeltipp_zurueck", "aktuell=\(ViewerProbe.text(scroll.zoomScale)) erwartet=\(ViewerProbe.text(expectedFit))")
        note("screenshot_eingepasst", ViewerProbe.snapshot(window, named: "viewer_probe_fit.jpg"))

        note("blaettern", subject.files.count > 1 ? "mehrere bilder in der nachricht=\(subject.files.count)" : "nur ein bild in der nachricht")
        flowLog.info("VIEWERPROBE fertig datei=\(subject.tapped, privacy: .public)")
    }
}
#endif
