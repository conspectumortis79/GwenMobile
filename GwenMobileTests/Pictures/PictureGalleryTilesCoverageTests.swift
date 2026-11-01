@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class PictureGalleryTilesCoverageTests: GwenTestCase {
    private func picture(_ index: Int) -> WebPicture {
        WebPicture(file: "web_\(index).jpg", pageURL: "https://q.test/\(index)",
                   fullURL: "https://cdn.q.test/\(index).jpg", title: "Bild \(index)", domain: "q.test")
    }

    private func gallery(pictures: [WebPicture], shown: Int, exhausted: Bool) -> PictureGallery {
        PictureGallery(query: "Bilder", pictures: pictures, shown: shown, exhausted: exhausted)
    }

    private func host(_ gallery: PictureGallery, feed: ImageFeed,
                      selection: GallerySelection = GallerySelection(),
                      operation: GalleryOperation = GalleryOperation(),
                      owner: UUID? = nil) -> UIHostingController<AnyView> {
        let view = PictureGalleryView(gallery: gallery, owner: owner, onOpen: { _ in },
                                      onOpenSource: { _ in }, onOpenOriginal: { _ in },
                                      onMore: {}, onShare: { _ in }, onSave: { _ in })
            .environmentObject(feed)
            .environmentObject(selection)
            .environmentObject(operation)
        return mountView(AnyView(view), size: CGSize(width: 390, height: 1200))
    }

    func testTheMorePlaceholderAndEndTilesDraw() async throws {
        let store = MediaStore(paths: temporaryPaths("gallery-tiles"))
        let feed = ImageFeed(reader: store)
        let more = host(gallery(pictures: (0..<8).map(picture), shown: 2, exhausted: false), feed: feed)
        try await settleHosted(more, milliseconds: 250)
        XCTAssertNotNil(more.view.window)
        let end = host(gallery(pictures: (0..<3).map(picture), shown: 3, exhausted: true), feed: feed)
        try await settleHosted(end, milliseconds: 250)
        XCTAssertNotNil(end.view.window)
        let empty = host(gallery(pictures: [], shown: 0, exhausted: false), feed: feed)
        try await settleHosted(empty, milliseconds: 250)
        XCTAssertNotNil(empty.view.window)
    }

    func testTheSearchingAndSelectionStatesDraw() async throws {
        let store = MediaStore(paths: temporaryPaths("gallery-searching"))
        let feed = ImageFeed(reader: store)
        let owner = UUID()
        let pictures = (0..<4).map(picture)
        let selection = GallerySelection()
        selection.begin(owner: owner)
        selection.toggle(pictures[0].file)
        let operation = GalleryOperation()
        operation.beginSearch(owner)
        let controller = host(gallery(pictures: pictures, shown: 4, exhausted: false), feed: feed,
                              selection: selection, operation: operation, owner: owner)
        try await settleHosted(controller, milliseconds: 300)
        XCTAssertNotNil(controller.view.window)
        operation.endSearch(owner)
        try await settleHosted(controller, milliseconds: 200)
        selection.end()
        try await settleHosted(controller, milliseconds: 200)
    }
}
