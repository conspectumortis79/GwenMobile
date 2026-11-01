@testable import GwenMobileAdapters
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class BusyOverlayTests: XCTestCase {
    func testRunningPublishesTheLabelAndReleasesItAfterwards() async {
        let busy = BusyOverlay()
        XCTAssertFalse(busy.isBusy)
        var labelDuringWork = ""
        let result = await busy.running(L.t("place_working")) {
            labelDuringWork = busy.label
            return 7
        }
        XCTAssertEqual(result, 7)
        XCTAssertEqual(labelDuringWork, "Suche Adressen in deiner Nähe")
        XCTAssertFalse(busy.isBusy)
        XCTAssertEqual(busy.label, "")
    }

    func testRunningReleasesTheOverlayEvenWhenTheWorkThrows() async {
        let busy = BusyOverlay()
        do {
            _ = try await busy.running(L.t("place_working")) { throw APIError(message: "fehler") }
            XCTFail("Arbeit hätte werfen müssen")
        } catch {
            XCTAssertFalse(busy.isBusy)
            XCTAssertEqual(busy.label, "")
        }
    }

    func testPictureLabelFollowsEditMode() {
        L.apply(.de)
        XCTAssertEqual(BusyOverlay.pictureLabel(editing: true), L.t("editing_image"))
        XCTAssertEqual(BusyOverlay.pictureLabel(editing: false), L.t("generating_image"))
    }

    func testANestedTaskHandsTheLabelBackToTheTaskThatContainsIt() async {
        L.apply(.de)
        let busy = BusyOverlay()
        var innerLabel = ""
        var outerLabelAfterInner = ""
        await busy.running(L.t("cal_working")) {
            _ = await busy.running(L.t("generating_image")) {
                innerLabel = busy.label
            }
            outerLabelAfterInner = busy.label
        }
        XCTAssertEqual(innerLabel, L.t("generating_image"))
        XCTAssertEqual(outerLabelAfterInner, "Kümmere mich um den Termin")
        XCTAssertFalse(busy.isBusy)
        XCTAssertEqual(busy.label, "")
    }

    func testAnInnerTaskNeverEndsTheOverlayOfTheOuterOne() async {
        let busy = BusyOverlay()
        await busy.running("aussen") {
            _ = await busy.running("innen") { }
            XCTAssertTrue(busy.isBusy)
            XCTAssertEqual(busy.label, "aussen")
        }
        XCTAssertFalse(busy.isBusy)
    }
}
