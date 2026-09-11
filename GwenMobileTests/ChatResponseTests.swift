import XCTest
@testable import GwenMobile

final class ChatResponseTests: XCTestCase {
    private func decode(_ json: String) -> ChatResponse? {
        try? JSONDecoder().decode(ChatResponse.self, from: Data(json.utf8))
    }

    func testStreamingDeltaContent() {
        let response = decode(#"{"choices":[{"delta":{"content":"hal"}}]}"#)
        XCTAssertEqual(response?.streamChunk, "hal")
        XCTAssertNil(response?.answerText)
    }

    func testNonStreamPlainTextAnswer() {
        let response = decode(#"{"choices":[{"message":{"role":"assistant","content":"fertig"}}]}"#)
        XCTAssertEqual(response?.answerText, "fertig")
        XCTAssertNil(response?.streamChunk)
    }

    func testImagePayloadUnderOutputChoices() {
        let response = decode(#"{"output":{"choices":[{"message":{"content":[{"image":"https://x/y.png"},{"text":"hinweis"}]}}]}}"#)
        let parts = response?.answerParts ?? []
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.first?.image, "https://x/y.png")
        XCTAssertEqual(parts.last?.text, "hinweis")
    }

    func testErrorPayloadIsReadable() {
        let response = decode(#"{"error":{"code":"InvalidParameter","message":"bad"}}"#)
        XCTAssertEqual(response?.error?.code, "InvalidParameter")
        XCTAssertEqual(response?.error?.message, "bad")
    }

    func testArrayContentHasNoPlainTextAnswer() {
        let response = decode(#"{"choices":[{"message":{"content":[{"type":"text","text":"x"}]}}]}"#)
        XCTAssertNil(response?.answerText)
        XCTAssertEqual(response?.answerParts?.count, 1)
    }

    func testUnknownExtraFieldsAreIgnored() {
        let response = decode(#"{"choices":[{"index":0,"finish_reason":"stop","delta":{"content":"a","reasoning_content":"r"}}]}"#)
        XCTAssertEqual(response?.streamChunk, "a")
    }
}
