@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class PromptLibraryFailureTests: GwenTestCase {
    func testAnUnreadablePromptFileComesBackEmpty() {
        let previous = PromptLibrary.stringReader
        PromptLibrary.stringReader = { _ in throw APIError(message: "kaputt") }
        defer {
            PromptLibrary.stringReader = previous
        }
        XCTAssertEqual(PromptLibrary.template("calendar_router"), "")
        XCTAssertEqual(PromptLibrary.field("args_tell_weather", "place"), "")
    }

    func testAnUnknownKeyComesBackEmpty() {
        XCTAssertEqual(PromptLibrary.template("gibt_es_nicht"), "")
    }

    func testFieldsSkipLinesWithoutAName() {
        let previous = PromptLibrary.stringReader
        PromptLibrary.stringReader = { _ in "name=value\n=ohne name\nohne gleich\nieer=" }
        defer {
            PromptLibrary.stringReader = previous
        }
        XCTAssertEqual(PromptLibrary.fields("calendar_router"), ["name": "value", "ieer": ""])
        XCTAssertEqual(PromptLibrary.field("calendar_router", "name"), "value")
        XCTAssertEqual(PromptLibrary.field("calendar_router", "fehlt"), "")
    }

    func testMissingPromptTokenFieldsStayEmpty() {
        let previous = PromptLibrary.stringReader
        PromptLibrary.stringReader = { _ in "other=value" }
        defer {
            PromptLibrary.stringReader = previous
        }
        XCTAssertEqual(PromptToken.picture, "")
        XCTAssertEqual(PromptToken.context, "")
        XCTAssertEqual(PromptToken.newQuestion, "")
    }
}
