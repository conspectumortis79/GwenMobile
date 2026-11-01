@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class FakeIdleCountdown: IdleCountdown {
    private var expiring: (@MainActor () -> Void)?
    private(set) var cancellations = 0

    func restart(after interval: Duration, expiring: @escaping @MainActor () -> Void) {
        self.expiring = expiring
    }

    func cancel() {
        expiring = nil
        cancellations += 1
    }

    func fire() { expiring?() }
}

@MainActor
final class GallerySelectionTests: GwenTestCase {
    private let owner = UUID()
    private let stranger = UUID()
    private let order = ["a.jpg", "b.jpg", "c.jpg", "d.jpg"]

    private func picture(_ file: String) -> WebPicture {
        WebPicture(file: file, pageURL: "https://q.test/seite", fullURL: "https://q.test/bild.jpg",
                   title: file, domain: "q.test")
    }

    private func gallery() -> PictureGallery {
        PictureGallery(query: "a", pictures: order.map(picture), shown: order.count, exhausted: true)
    }

    func testATapOutsideThePickingModeStillOpensThePicture() {
        let selection = GallerySelection()
        XCTAssertEqual(selection.tap("a.jpg", owner: owner, in: order), .openPreview)
        XCTAssertFalse(selection.isPicking, "ein normaler Tipp darf nie eine Auswahl starten")
        XCTAssertTrue(selection.files.isEmpty)
    }

    func testOnlyTheSelectButtonOpensThePickingMode() {
        let selection = GallerySelection()
        selection.begin(owner: owner)
        XCTAssertTrue(selection.picking(owner))
        XCTAssertTrue(selection.isEmpty, "der Modus startet leer")
        selection.selectAll(order)
        XCTAssertEqual(selection.count, order.count)
    }

    func testATapInsideThePickingModePicksAndDropsThePicture() {
        let selection = GallerySelection()
        selection.begin(owner: owner)
        XCTAssertEqual(selection.tap("a.jpg", owner: owner, in: order), .selected)
        XCTAssertEqual(selection.tap("b.jpg", owner: owner, in: order), .selected)
        XCTAssertEqual(selection.tap("a.jpg", owner: owner, in: order), .deselected)
        XCTAssertEqual(selection.files, ["b.jpg"])
    }

    func testSelectAllNeedsTheModeToBeOpenAlready() {
        let selection = GallerySelection()
        selection.selectAll(order)
        XCTAssertFalse(selection.isPicking)
        XCTAssertTrue(selection.isEmpty, "ohne Auswählen-Knopf wird nichts angewählt")
    }

    func testTheLongPressEntryPicksOnePictureAndTurnsTheModeOn() {
        let selection = GallerySelection()
        selection.begin(owner: owner)
        XCTAssertEqual(selection.toggle("b.jpg"), .selected)
        XCTAssertEqual(selection.toggle("b.jpg"), .deselected)
        XCTAssertTrue(selection.isEmpty)
    }

    func testSelectingAnotherGalleryEndsTheFirstOneCleanly() {
        let selection = GallerySelection()
        selection.begin(owner: owner)
        selection.toggle("a.jpg")
        selection.begin(owner: stranger)
        XCTAssertFalse(selection.picking(owner))
        XCTAssertTrue(selection.picking(stranger))
        XCTAssertTrue(selection.isEmpty)
    }

    func testCommandTapAddsAndRemovesWithoutTouchingTheRest() {
        let selection = GallerySelection()
        selection.begin(owner: owner)
        selection.toggle("a.jpg")
        XCTAssertEqual(selection.tap("c.jpg", owner: owner, in: order, mode: .adding), .selected)
        XCTAssertEqual(selection.files, ["a.jpg", "c.jpg"])
        XCTAssertEqual(selection.tap("a.jpg", owner: owner, in: order, mode: .adding), .deselected)
        XCTAssertEqual(selection.files, ["c.jpg"])
    }

    func testShiftTapSelectsTheSpanFromTheLastTappedPicture() {
        let selection = GallerySelection()
        selection.tap("a.jpg", owner: owner, in: order, mode: .adding)
        selection.tap("d.jpg", owner: owner, in: order, mode: .adding)
        XCTAssertEqual(selection.tap("c.jpg", owner: owner, in: order, mode: .range), .selected)
        XCTAssertEqual(selection.files, Set(["c.jpg", "d.jpg"]))
    }

    func testOptionTapAsksForASingleSaveAndLeavesTheSelectionAlone() {
        let selection = GallerySelection()
        selection.begin(owner: owner)
        selection.toggle("a.jpg")
        XCTAssertEqual(selection.tap("b.jpg", owner: owner, in: order, mode: .saving), .saveOne)
        XCTAssertEqual(selection.files, ["a.jpg"])
    }

    func testSelectAllCoversEveryVisiblePicture() {
        let selection = GallerySelection()
        selection.begin(owner: owner)
        selection.selectAll(order)
        XCTAssertEqual(selection.count, order.count)
    }

    func testEndingTheModeForgetsEverything() {
        let selection = GallerySelection()
        selection.begin(owner: owner)
        selection.selectAll(order)
        selection.end()
        XCTAssertFalse(selection.isPicking)
        XCTAssertTrue(selection.files.isEmpty)
    }

    func testThePicturesFollowTheOrderOfTheGalleryAndNotTheTapOrder() {
        let selection = GallerySelection()
        selection.tap("d.jpg", owner: owner, in: order, mode: .adding)
        selection.tap("a.jpg", owner: owner, in: order, mode: .adding)
        XCTAssertEqual(selection.pictures(in: gallery()).map(\.file), ["a.jpg", "d.jpg"])
    }

    func testNothingIsSelectedForAnUnknownMessage() {
        let selection = GallerySelection()
        selection.begin(owner: owner)
        XCTAssertFalse(selection.picking(nil))
        XCTAssertEqual(selection.pictures(in: nil).count, 0)
    }

    func testBeginningTheSameGalleryTwiceKeepsTheSelection() {
        let selection = GallerySelection()
        selection.begin(owner: owner)
        selection.toggle("a.jpg")
        selection.begin(owner: owner)
        XCTAssertEqual(selection.files, ["a.jpg"])
    }

    func testARangeTapWithAnAnchorOutsideTheGalleryFallsBackToASinglePick() {
        let selection = GallerySelection()
        selection.toggle("weg.jpg")
        XCTAssertEqual(selection.tap("b.jpg", owner: owner, in: order, mode: .range), .selected)
        XCTAssertEqual(selection.files, ["b.jpg"])
    }
}
