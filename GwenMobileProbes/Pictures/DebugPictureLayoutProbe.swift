@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum DebugPictureLayoutProbe {
    static let shapes: [CGSize] = [
        CGSize(width: 1200, height: 400), CGSize(width: 500, height: 900),
        CGSize(width: 700, height: 700), CGSize(width: 300, height: 1000),
        CGSize(width: 1400, height: 500), CGSize(width: 640, height: 480),
        CGSize(width: 480, height: 1200), CGSize(width: 900, height: 300),
        CGSize(width: 800, height: 800), CGSize(width: 1000, height: 250),
        CGSize(width: 260, height: 780), CGSize(width: 720, height: 540),
        CGSize(width: 1500, height: 600), CGSize(width: 550, height: 1100),
        CGSize(width: 620, height: 620), CGSize(width: 1100, height: 350),
        CGSize(width: 340, height: 900), CGSize(width: 860, height: 640),
    ]

    private static let colours: [UIColor] = [
        .systemTeal, .systemIndigo, .systemOrange, .systemPink,
    ]

    private static let kinds: [PictureProbe.Kind] = [
        .ellipse, .rectangle, .roundedRectangle, .triangle, .star,
    ]

    static func gallery(_ view: ChatView) async {
        let report = SweepReport(file: "picture_layout.txt")
        let media = view.store.media
        let pictures = storedPictures(in: media)
        guard pictures.count == shapes.count,
              let window = Presenter.windowRootViewController?.view?.window else {
            report.add("aufbau", "bilder=\(pictures.count)/\(shapes.count) fenster="
                       + "\(Presenter.windowRootViewController?.view.window != nil)")
            return
        }
        view.store.newConversation()
        guard let conversation = view.store.currentID else {
            report.add("aufbau", "keine unterhaltung")
            return
        }
        append(gallery: gallery(pictures, query: "brooke shields"), to: conversation, store: view.store)
        append(gallery: gallery(pictures, query: "brooke shields 2024"), to: conversation, store: view.store)
        view.store.appendMessage(ChatMessage(role: .user, text: "danke, das reicht"), to: conversation)
        view.store.appendAssistant("Gern — die Raster stehen still.", model: "probe", elapsed: 1,
                                   to: conversation)

        guard let scroll = threadScroll(in: window) else {
            report.add("messen", "kein scroll-view gefunden")
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        let before = scroll.contentSize.height
        await waitUntilDecoded(pictures, feed: view.store.images)
        try? await Task.sleep(for: .milliseconds(500))
        let after = scroll.contentSize.height
        let shown = ImagePolicy.galleryInitialItems
        report.add("messen", "kacheln_pro_antwort=\(min(shown, pictures.count)) geladen=\(pictures.count) "
                   + "hoehe_vor_dem_laden=\(Int(before)) hoehe_danach=\(Int(after)) "
                   + "sprung=\(Int(after - before)) rutschfrei=\(abs(after - before) < 2)")
        report.add("raster", "zeilen=\(GalleryGrid.rows(Array(0..<shown)).count) "
                   + "pro_zeile=\(GalleryGrid.tilesPerRow) kachel=\(Int(GalleryGrid.side))pt "
                   + "breite=\(Int(GalleryGrid.width))pt fenster=\(Int(scroll.bounds.width))pt")
        report.add("screenshot", ViewerProbe.snapshot(window, named: "picture_layout.jpg"))
        flowLog.info("BILDLAYOUT fertig")
    }

    private static func gallery(_ pictures: [WebPicture], query: String) -> PictureGallery {
        PictureGallery(query: query, pictures: pictures,
                       shown: ImagePolicy.galleryInitialItems, exhausted: false)
    }

    private static func append(gallery: PictureGallery, to conversation: UUID, store: ChatStore) {
        store.appendMessage(ChatMessage(role: .user, text: "zeig mir bilder von \(gallery.query)"),
                            to: conversation)
        store.appendAssistant(ChatView.galleryAnswer(gallery: gallery, failures: 0), model: "probe",
                              elapsed: 1, to: conversation,
                              sources: gallery.chipSources.nilIfEmpty, gallery: gallery)
    }

    private static func storedPictures(in media: MediaStore) -> [WebPicture] {
        shapes.enumerated().compactMap { index, size in
            let fixture = PictureProbe.Fixture(file: "layout_\(index).jpg", shape: "form", colour: "farbe",
                                               canvas: size,
                                               background: colours[index % colours.count].withAlphaComponent(0.22),
                                               object: colours[index % colours.count],
                                               kind: kinds[index % kinds.count])
            guard let data = fixture.image().jpegData(compressionQuality: 0.8),
                  let file = media.storeImageData(data) else { return nil }
            return WebPicture(file: file, pageURL: "https://q\(index).test/seite",
                              fullURL: "https://cdn.q\(index).test/original.jpg",
                              title: "Layout-Bild \(index)", domain: "q\(index).test")
        }
    }

    private static func threadScroll(in view: UIView) -> UIScrollView? {
        let found = ViewSearching.scrolls(in: view)
        return found.first { $0.contentSize.height > $0.bounds.height + 40 } ?? found.max(by: {
            $0.contentSize.height < $1.contentSize.height
        })
    }

    private static func waitUntilDecoded(_ pictures: [WebPicture], feed: ImageFeed) async {
        for picture in pictures { feed.load(picture.file) }
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if pictures.allSatisfy({ feed.rendition(for: $0.file) != nil }) { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
#endif
