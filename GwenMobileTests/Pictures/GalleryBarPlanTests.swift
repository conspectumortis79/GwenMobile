@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class GalleryBarPlanTests: GwenTestCase {
    private func plan(selected: Int, total: Int, progress: GalleryProgress? = nil,
                      result: GalleryResult? = nil) -> GalleryBarPlan {
        GalleryBarPlan.make(selected: selected, total: total, progress: progress, result: result)
    }

    func testTheIdleLineCountsTheSelection() {
        XCTAssertEqual(plan(selected: 3, total: 18).statusLine, "3 selected")
        XCTAssertEqual(plan(selected: 1, total: 18).statusLine, "1 selected")
    }

    func testTheSaveButtonNamesTheCountOnlyForSeveralPictures() {
        XCTAssertEqual(plan(selected: 1, total: 18).saveTitle, "Save to Photos")
        XCTAssertEqual(plan(selected: 3, total: 18).saveTitle, "Save 3 to Photos")
    }

    func testTheShareButtonAlwaysOffersTheSystemSheet() {
        XCTAssertEqual(plan(selected: 2, total: 18).shareTitle, "Share")
    }

    func testWhileWritingTheLineReportsEveryStep() {
        let busy = plan(selected: 3, total: 18, progress: GalleryProgress(total: 3, done: 2))
        XCTAssertEqual(busy.statusLine, "Saving 2 of 3 …")
        XCTAssertFalse(busy.canAct, "nichts darf zweimal in die Bibliothek geschrieben werden")
    }

    func testTheResultLineReportsWhatLandedInTheLibrary() {
        XCTAssertEqual(plan(selected: 3, total: 18, result: .saved(3)).statusLine,
                       "✔ 3 images saved to Photos")
        XCTAssertEqual(plan(selected: 1, total: 18, result: .saved(1)).statusLine, "✔ Image saved to Photos")
        XCTAssertEqual(plan(selected: 3, total: 18, result: .denied).statusLine,
                       L.t("photos_not_allowed"))
        XCTAssertEqual(plan(selected: 3, total: 18, result: .failed).statusLine, L.t("save_failed"))
    }

    func testSaveAllAppearsOnlyForAPartialSelection() {
        XCTAssertTrue(plan(selected: 3, total: 18).showsSaveAll)
        XCTAssertFalse(plan(selected: 18, total: 18).showsSaveAll)
        XCTAssertFalse(plan(selected: 0, total: 18).showsSaveAll)
        XCTAssertEqual(plan(selected: 3, total: 18).saveAllTitle, "Save all 18")
    }

    func testAnEmptySelectionOffersNothing() {
        XCTAssertFalse(plan(selected: 0, total: 18).canAct)
    }

    func testAfterASuccessfulSaveTheBarIsOnlyAConfirmation() {
        let done = plan(selected: 0, total: 18, result: .saved(3))
        XCTAssertTrue(done.isConfirmation)
        XCTAssertEqual(done.resultSymbol, "checkmark.circle.fill")
        XCTAssertEqual(done.statusLine, "✔ 3 images saved to Photos")
    }

    func testAFailedSaveKeepsTheSelectionSoTheUserCanTryAgain() {
        let refused = plan(selected: 3, total: 18, result: .denied)
        XCTAssertFalse(refused.isConfirmation, "die Auswahl ist noch da, also ist die Zeile keine Bestaetigung")
        XCTAssertTrue(refused.canAct, "ein zweiter Versuch darf nicht gesperrt sein")
        XCTAssertEqual(refused.resultSymbol, "exclamationmark.circle.fill")
    }

    func testNothingIsConfirmedWithoutAResult() {
        XCTAssertFalse(plan(selected: 0, total: 18).isConfirmation)
        XCTAssertFalse(plan(selected: 2, total: 18).isConfirmation)
    }

    func testTheProgressFractionStopsAtOne() {
        XCTAssertEqual(GalleryProgress(total: 4, done: 1).fraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(GalleryProgress(total: 4, done: 9).fraction, 1, accuracy: 0.0001)
        XCTAssertEqual(GalleryProgress(total: 0, done: 0).fraction, 0, accuracy: 0.0001)
    }
}

@MainActor
final class GalleryOperationTests: GwenTestCase {
    private func subject() -> (GalleryOperation, FakeIdleCountdown) {
        let idle = FakeIdleCountdown()
        return (GalleryOperation(idle: idle, resultLifetime: .seconds(4)), idle)
    }

    func testSavingCountsEveryPictureAndNeverPastTheTotal() {
        let (operation, _) = subject()
        operation.beginSaving(total: 3)
        XCTAssertEqual(operation.saving?.done, 0)
        operation.advanceSaving()
        operation.advanceSaving()
        operation.advanceSaving()
        operation.advanceSaving()
        XCTAssertEqual(operation.saving, GalleryProgress(total: 3, done: 3))
    }

    func testAFinishedSaveLeavesTheResultAndDropsTheProgress() {
        let (operation, idle) = subject()
        operation.beginSaving(total: 2)
        operation.finishSaving(.saved(2))
        XCTAssertNil(operation.saving)
        XCTAssertEqual(operation.result, .saved(2))
        XCTAssertTrue(operation.showsBar)
        idle.fire()
        XCTAssertNil(operation.result)
        XCTAssertFalse(operation.showsBar)
    }

    func testADeniedLibraryIsReportedAsItsOwnResult() {
        let (operation, _) = subject()
        operation.beginSaving(total: 2)
        operation.finishSaving(.denied)
        XCTAssertEqual(operation.result, .denied)
    }

    func testARefusedSaveStartsTheNextAttemptClean() {
        let (operation, _) = subject()
        operation.finishSaving(.failed)
        operation.beginSaving(total: 1)
        XCTAssertNil(operation.result)
        XCTAssertEqual(operation.saving, GalleryProgress(total: 1, done: 0))
    }

    func testTheSearchingFlagNamesOnlyTheMessageThatAsked() {
        let (operation, _) = subject()
        let first = UUID()
        let second = UUID()
        operation.beginSearch(first)
        XCTAssertTrue(operation.isSearching(first))
        XCTAssertFalse(operation.isSearching(second))
        XCTAssertFalse(operation.isSearching(nil))
        operation.endSearch(first)
        XCTAssertFalse(operation.isSearching(first))
    }
}
