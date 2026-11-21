@testable import GwenMobileFeatureCore
import XCTest

final class PictureExactInstructionTests: GwenTestCase {
    func testTheExactToolValuesAreParsed() {
        XCTAssertEqual(PictureExactEdit.list(from: ["crop_left_half"]), [.cropLeftHalf])
        XCTAssertEqual(PictureExactEdit.list(from: ["crop_left_half", "red_dot_center"]),
                       [.cropLeftHalf, .redDotCenter])
        XCTAssertEqual(PictureExactEdit.list(from: "red_dot_center"), [.redDotCenter])
        XCTAssertEqual(PictureExactEdit.list(from: ["unknown"]), [])
        XCTAssertEqual(PictureExactEdit.list(from: nil), [])
    }

    func testTheCropPromptNamesTheLeftHalf() {
        let prompt = PictureExactInstruction([.cropLeftHalf]).prompt(replacing: "fallback")
        XCTAssertTrue(prompt.contains("left 50"))
        XCTAssertTrue(prompt.contains("half as wide"))
        XCTAssertTrue(prompt.contains("Do not rotate"))
        XCTAssertFalse(prompt.contains("fallback"))
    }

    func testTheDotPromptNamesTheCentre() {
        let prompt = PictureExactInstruction([.redDotCenter]).prompt(replacing: "fallback")
        XCTAssertTrue(prompt.contains("red circular dot"))
        XCTAssertTrue(prompt.contains("centre"))
        XCTAssertTrue(prompt.contains("Do not rotate"))
    }

    func testBothOperationsAndBlackAndWhiteAreCarried() {
        let prompt = PictureExactInstruction([.cropLeftHalf, .redDotCenter])
            .prompt(replacing: "fallback", blackAndWhite: true)
        XCTAssertTrue(prompt.contains("left 50"))
        XCTAssertTrue(prompt.contains("red circular dot"))
        XCTAssertTrue(prompt.contains("black and white"))
    }

    func testAnEmptyExactOperationKeepsTheFallback() {
        XCTAssertEqual(PictureExactInstruction([]).prompt(replacing: "fallback"), "fallback")
    }
}
