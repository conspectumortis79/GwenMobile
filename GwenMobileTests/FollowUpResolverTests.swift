import XCTest
@testable import GwenMobile

final class FollowUpResolverTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    private func message(_ role: Role, _ text: String) -> ChatMessage {
        ChatMessage(role: role, text: text)
    }

    func testFollowUpsAreRecognisedAsContextDependent() {
        for text in ["und in Deutschland?", "mach daraus ein diagramm", "was ist damit gemeint?",
                     "wie gesagt, noch einmal genauer", "what about the neighbours?", "und beim letzten mal?",
                     "erklär das nochmal", "davon habe ich noch nie gehört"] {
            XCTAssertTrue(FollowUpResolver.needsContext(text), text)
        }
    }

    func testStandaloneQuestionsNeedNoRewrite() {
        for text in ["Was ist die Hauptstadt von Frankreich?",
                     "Welche Folgen hat der Meeresspiegelanstieg für die Küstenstädte?",
                     "Erkläre mir, wie eine Wärmepumpe funktioniert"] {
            XCTAssertFalse(FollowUpResolver.needsContext(text), text)
        }
        XCTAssertFalse(FollowUpResolver.needsContext("   "))
    }

    func testRequestMessagesCarryRecentContextAndTheNewQuestion() {
        var history = [message(.user, "Was sind die Hauptursachen der Klimaerwärmung?"),
                       message(.assistant, "Fossile Energieträger, Industrie, Landwirtschaft.")]
        for index in 0..<8 {
            history.append(message(index.isMultiple(of: 2) ? .user : .assistant, "Nachricht \(index)"))
        }
        history.append(message(.user, "und in Deutschland?"))
        let text = FollowUpResolver.requestMessages(text: "und in Deutschland?", history: history).first?.text ?? ""
        XCTAssertTrue(text.hasPrefix("KONTEXT:\n"))
        XCTAssertTrue(text.contains("Nachricht 7"))
        XCTAssertTrue(text.contains("NEUE FRAGE:\nund in Deutschland?"))
        XCTAssertFalse(text.contains("Nachricht 1"), "ältere Nachrichten fallen heraus")
        let contextLines = text.components(separatedBy: "\n")
            .filter { $0.hasPrefix("user:") || $0.hasPrefix("assistant:") }
        XCTAssertEqual(contextLines.count, ConversationTranscript.defaultLimit)
    }

    func testLongHistoryMessagesAreCappedAndKeptOnOneLine() {
        let history = [message(.user, "Erzähl was über Solarzellen"),
                       message(.assistant, String(repeating: "wort ", count: 500) + "\nZEILE2"),
                       message(.user, "und daraus?")]
        let text = FollowUpResolver.requestMessages(text: "und daraus?", history: history).first?.text ?? ""
        XCTAssertTrue(text.contains("wort"))
        XCTAssertFalse(text.contains("ZEILE2"))
        XCTAssertTrue(text.contains("und daraus?"))
        let assistantLine = text.components(separatedBy: "\n").first { $0.hasPrefix("assistant:") } ?? ""
        XCTAssertLessThanOrEqual(assistantLine.count, ConversationTranscript.defaultCap + 20)
    }

    func testSanitizeTakesOneCleanQueryLine() {
        XCTAssertEqual(FollowUpResolver.sanitize("\n  \"Hauptursachen der Klimaerwärmung in Deutschland\"  \nDanke!"),
                       "Hauptursachen der Klimaerwärmung in Deutschland")
        XCTAssertEqual(FollowUpResolver.sanitize("Suchanfrage: Einwohnerzahl Deutschland 2024"),
                       "Einwohnerzahl Deutschland 2024")
        XCTAssertEqual(FollowUpResolver.sanitize("query: population of germany"), "population of germany")
        XCTAssertEqual(FollowUpResolver.sanitize(String(repeating: "a", count: 400)).count,
                       FollowUpResolver.maxQueryChars)
    }

    func testUsabilityGateRejectsEverythingThatIsNotAQuery() {
        XCTAssertFalse(FollowUpResolver.isUsable("zu kurz", insteadOf: "und in Deutschland?"))
        XCTAssertFalse(FollowUpResolver.isUsable("und in Deutschland?", insteadOf: " und in Deutschland? "))
        XCTAssertFalse(FollowUpResolver.isUsable("Das kann ich nicht beantworten.", insteadOf: "und in Deutschland?"))
        XCTAssertFalse(FollowUpResolver.isUsable(String(repeating: "a", count: 300), insteadOf: "und in Deutschland?"))
        XCTAssertTrue(FollowUpResolver.isUsable("Hauptursachen der Klimaerwärmung in Deutschland",
                                                insteadOf: "und in Deutschland?"))
    }

    func testInstructionsDemandASingleStandaloneQuery() {
        let instructions = Prompt.Research.followUpQuery()
        XCTAssertTrue(instructions.contains("standalone search query"))
        XCTAssertTrue(instructions.contains("only that query on a single line"))
        XCTAssertTrue(instructions.contains("already self-contained, repeat it unchanged"))
        XCTAssertTrue(instructions.contains("und in Deutschland?"))
        XCTAssertTrue(instructions.contains("[image attached]"))
        XCTAssertTrue(instructions.contains("[generated image]"))
    }
}
