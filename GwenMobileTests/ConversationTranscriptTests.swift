import XCTest
@testable import GwenMobile

final class ConversationTranscriptTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    func testEveryTurnBecomesOneLineWithItsRole() {
        let messages = [ChatMessage(role: .user, text: "Wie spät ist es?"),
                        ChatMessage(role: .assistant, text: "Zwölf Uhr.\nUnd weiter."),
                        ChatMessage(role: .user, text: "und in New York?")]
        XCTAssertEqual(ConversationTranscript.withoutTheNewestQuestion(from: messages),
                       "user: Wie spät ist es?\nassistant: Zwölf Uhr. Und weiter.")
        XCTAssertTrue(ConversationTranscript.from(messages: []).isEmpty)
    }

    func testPicturesAreNamedSoTheModelCanReferToThem() {
        let messages = [ChatMessage(role: .user, text: "Was ist das?", images: [Attachment(file: "a.jpg")]),
                        ChatMessage(role: .assistant, text: "Ein Turm.", outImages: [Attachment(file: "t.jpg")])]
        let transcript = ConversationTranscript.from(messages: messages)
        XCTAssertTrue(transcript.contains("user: Was ist das? [image attached]"), transcript)
        XCTAssertTrue(transcript.contains("assistant: Ein Turm. [generated image]"), transcript)
    }

    func testOldTurnsAndLongAnswersAreCapped() {
        let messages = (0..<10).map { index in
            ChatMessage(role: index.isMultiple(of: 2) ? .user : .assistant,
                        text: "Nachricht \(index) " + String(repeating: "x", count: 500))
        }
        let lines = ConversationTranscript.from(messages: messages).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, ConversationTranscript.defaultLimit)
        XCTAssertEqual(lines.first?.count, ConversationTranscript.defaultCap + 6)
        XCTAssertTrue(lines.last?.hasPrefix("assistant:") ?? false)
    }
}
