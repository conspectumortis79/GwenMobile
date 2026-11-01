@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ConversationTranscriptTests: GwenTestCase {
    func testEveryTurnBecomesOneLineWithItsRole() {
        let messages = [ChatMessage(role: .user, text: "Wie spät ist es?"),
                        ChatMessage(role: .assistant, text: "Zwölf Uhr.\nUnd weiter."),
                        ChatMessage(role: .user, text: "und in New York?")]
        XCTAssertEqual(ConversationTranscript.withoutTheNewestQuestion(from: messages),
                       "user: Wie spät ist es?\nassistant: Zwölf Uhr. Und weiter.")
        XCTAssertTrue(ConversationTranscript.from(messages: []).isEmpty)
    }

    func testOnlyTheQuestionLeavesWhileAnAnswerAfterItStays() {
        let messages = [ChatMessage(role: .user, text: "Erste Frage"),
                        ChatMessage(role: .assistant, text: "Erste Antwort"),
                        ChatMessage(role: .user, text: "Zweite Frage"),
                        ChatMessage(role: .assistant, text: "Zweiter Schritt")]
        XCTAssertEqual(ConversationTranscript.withoutTheNewestQuestion(from: messages),
                       "user: Erste Frage\nassistant: Erste Antwort\nassistant: Zweiter Schritt")
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

    func testOnlyTheLatestAnswerGetsTheWideCap() {
        let messages = [ChatMessage(role: .assistant, text: String(repeating: "a", count: 900)),
                        ChatMessage(role: .user, text: "und weiter?"),
                        ChatMessage(role: .assistant,
                                    text: String(repeating: "y", count: ConversationTranscript.defaultAnswerCap + 500))]
        let lines = ConversationTranscript.from(messages: messages).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].count, "assistant: ".count + ConversationTranscript.defaultCap)
        XCTAssertEqual(lines[2].count, "assistant: ".count + ConversationTranscript.defaultAnswerCap)
    }

    func testEveryItemOfTheEarlierNewsAnswerReachesTheTranscript() {
        let answer = (1...5).map { "- **Meldung \($0)**: " + String(repeating: "Text ", count: 30) }
            .joined(separator: "\n")
        let messages = [ChatMessage(role: .user, text: "aktuelle Nachrichten aus Berlin"),
                        ChatMessage(role: .assistant, text: answer),
                        ChatMessage(role: .user, text: "bitte je Meldung mehr Information dazu")]
        let transcript = ConversationTranscript.withoutTheNewestQuestion(from: messages)
        XCTAssertGreaterThan(answer.count, ConversationTranscript.defaultCap)
        for index in 1...5 {
            XCTAssertTrue(transcript.contains("Meldung \(index)"), transcript)
        }
        XCTAssertFalse(transcript.contains("mehr Information"), "die neue Frage ist kein Verlauf")
    }
}
