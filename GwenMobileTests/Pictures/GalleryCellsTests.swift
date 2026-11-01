@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class GalleryCellsTests: GwenTestCase {
    private func picture(_ file: String) -> WebPicture {
        WebPicture(file: file, pageURL: "https://q.test/seite", fullURL: "https://q.test/bild.jpg",
                   title: file, domain: "q.test")
    }

    private func files(_ count: Int) -> [WebPicture] {
        (1...count).map { picture("f\($0).jpg") }
    }

    private func gallery(_ count: Int, shown: Int, exhausted: Bool) -> PictureGallery {
        PictureGallery(query: "a", pictures: files(count), shown: shown, exhausted: exhausted)
    }

    func testHiddenPicturesBecomeOneMoreTileAtTheEndOfTheGrid() {
        let cells = GalleryLayout.cells(gallery(18, shown: 12, exhausted: false), searching: false)
        XCTAssertEqual(cells.count, 13)
        XCTAssertEqual(cells.last, .more(.hidden(6)))
    }

    func testAFullyShownButOpenGalleryPromisesTheNextRound() {
        let cells = GalleryLayout.cells(gallery(18, shown: 18, exhausted: false), searching: false)
        XCTAssertEqual(cells.last, .more(.nextRound(ImagePolicy.galleryMaxStored)))
        XCTAssertEqual(cells.count, 19)
    }

    func testAnExhaustedGalleryEndsWithAQuietTileInsteadOfADeadButton() {
        let cells = GalleryLayout.cells(gallery(6, shown: 12, exhausted: true), searching: false)
        XCTAssertEqual(cells.count, 7)
        XCTAssertEqual(cells.last, .endOfResults)
    }

    func testWhileTheRoundRunsTheGridShowsPlaceholdersAndOneSearchingTile() {
        let cells = GalleryLayout.cells(gallery(12, shown: 12, exhausted: false), searching: true)
        let placeholders = cells.filter { if case .placeholder = $0 { return true } else { return false } }
        XCTAssertEqual(placeholders.count, ImagePolicy.galleryLoadingPlaceholders)
        XCTAssertEqual(cells.last, .searching)
        XCTAssertEqual(cells.first, .picture(picture("f1.jpg")))
    }

    func testEveryCellStaysUniqueSoTheGridNeverDuplicatesARow() {
        let cells = GalleryLayout.cells(gallery(12, shown: 12, exhausted: false), searching: true)
        XCTAssertEqual(Set(cells.map(\.id)).count, cells.count)
    }

    func testTheTilesPerRowRuleHoldsForCellRowsToo() {
        let cells = GalleryLayout.cells(gallery(18, shown: 12, exhausted: false), searching: false)
        XCTAssertEqual(GalleryGrid.rows(cells).map(\.count), [3, 3, 3, 3, 1])
    }

    func testTheMoreTileCountsWhatItWillBring() {
        XCTAssertEqual(GalleryMoreKind.hidden(6).count, 6)
        XCTAssertEqual(GalleryMoreKind.nextRound(24).count, 24)
        XCTAssertTrue(GalleryMoreKind.nextRound(24).isRound)
        XCTAssertFalse(GalleryMoreKind.hidden(6).isRound)
    }
}
