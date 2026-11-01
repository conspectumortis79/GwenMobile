@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

@MainActor
final class PictureGalleryLayoutTests: GwenTestCase {
    private var mixed: [CGSize] { DebugPictureLayoutProbe.shapes }

    private func gallery(_ store: MediaStore, shapes: [CGSize]) -> PictureGallery {
        let pictures = shapes.enumerated().compactMap { index, size -> WebPicture? in
            guard let data = FakePicture.make(size).jpegData(compressionQuality: 0.8),
                  let file = store.storeImageData(data) else { return nil }
            return WebPicture(file: file, pageURL: "https://q\(index).test/s",
                              fullURL: "https://cdn.q\(index).test/o.jpg",
                              title: "Bild \(index)", domain: "q\(index).test")
        }
        return PictureGallery(query: "brooke shields", pictures: pictures,
                              shown: pictures.count, exhausted: true)
    }

    private func host(_ gallery: PictureGallery, feed: ImageFeed) -> UIHostingController<AnyView> {
        let view = PictureGalleryView(gallery: gallery, owner: nil, onOpen: { _ in },
                                      onOpenSource: { _ in }, onOpenOriginal: { _ in },
                                      onMore: {}, onShare: { _ in }, onSave: { _ in })
            .environmentObject(feed)
            .environmentObject(GallerySelection())
            .environmentObject(GalleryOperation())
        let controller = UIHostingController(rootView: AnyView(view))
        controller.view.frame = CGRect(x: 0, y: 0, width: 360, height: 1600)
        if let window = Presenter.windowRootViewController?.view.window {
            window.addSubview(controller.view)
        }
        addTeardownBlock {
            controller.view.removeFromSuperview()
        }
        return controller
    }

    private func fittedHeight(_ controller: UIHostingController<AnyView>) -> CGFloat {
        controller.sizeThatFits(in: CGSize(width: 360,
                                           height: UIView.layoutFittingExpandedSize.height)).height
    }

    private func decode(_ gallery: PictureGallery, feed: ImageFeed) async {
        gallery.pictures.forEach { feed.load($0.file) }
        await waitUntil { gallery.pictures.allSatisfy { feed.rendition(for: $0.file) != nil } }
    }

    func testTheGalleryStandsStillWhileThePreviewsArrive() async throws {
        let store = scratchMediaStore()
        let gallery = self.gallery(store, shapes: mixed)
        XCTAssertEqual(gallery.pictures.count, mixed.count, "die Messung braucht 18 Bilder")
        let feed = ImageFeed(reader: store)
        let controller = host(gallery, feed: feed)

        let before = fittedHeight(controller)
        XCTAssertTrue(gallery.pictures.allSatisfy { feed.rendition(for: $0.file) == nil })
        await decode(gallery, feed: feed)

        XCTAssertEqual(fittedHeight(controller), before, accuracy: 1,
                       "die Höhe darf nicht springen, wenn die Bilder reinkommen — die nächste Blase steht sonst darüber")
    }

    func testTheGridHeightIgnoresTheProportionsOfThePictures() async throws {
        let store = scratchMediaStore()
        let squares = self.gallery(store, shapes: Array(repeating: CGSize(width: 900, height: 900),
                                                        count: mixed.count))
        let mixedGallery = self.gallery(store, shapes: mixed)
        let squareFeed = ImageFeed(reader: store)
        let mixedFeed = ImageFeed(reader: store)
        let squareHost = host(squares, feed: squareFeed)
        let mixedHost = host(mixedGallery, feed: mixedFeed)
        await decode(squares, feed: squareFeed)
        await decode(mixedGallery, feed: mixedFeed)

        XCTAssertEqual(fittedHeight(mixedHost), fittedHeight(squareHost), accuracy: 1,
                       "18 Kacheln sind 6 Zeilen, egal ob Querformat oder Hochformat")
    }

    func testTheGridStaysInsideTheNarrowestBubble() {
        let narrowestiPhoneContentWidth: CGFloat = 375 - 2 * 12
        XCTAssertLessThanOrEqual(GalleryGrid.width, narrowestiPhoneContentWidth,
                                 "auf dem kleinsten Gerät darf die Galerie nicht aus der Blase laufen")
    }

    func testTheRowSplitKeepsThreePerRowAndTheRestAlone() {
        XCTAssertEqual(GalleryGrid.rows([Int]()), [])
        XCTAssertEqual(GalleryGrid.rows([1, 2]).map { $0.count }, [2])
        XCTAssertEqual(GalleryGrid.rows(Array(1...18)).count, 6)
        XCTAssertEqual(GalleryGrid.rows(Array(1...18)).map { $0.count }, [3, 3, 3, 3, 3, 3])
        XCTAssertEqual(GalleryGrid.rows(Array(1...7)).map { $0.count }, [3, 3, 1])
        XCTAssertEqual(GalleryGrid.rows(Array(1...7)).flatMap { $0 }, Array(1...7),
                       "die Reihenfolge der Fundstücke bleibt die der Suche")
    }
}
