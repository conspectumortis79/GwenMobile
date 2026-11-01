@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class FollowUpResolverTests: GwenTestCase {
    private func message(_ role: Role, _ text: String) -> ChatMessage {
        ChatMessage(role: role, text: text)
    }

    func testRequestMessagesCarryRecentContextAndTheNewQuestion() {
        var history = [message(.user, "Was sind die Hauptursachen der Klimaerwärmung?"),
                       message(.assistant, "Fossile Energieträger, Industrie, Landwirtschaft.")]
        for index in 0..<8 {
            history.append(message(index.isMultiple(of: 2) ? .user : .assistant, "Nachricht \(index)"))
        }
        history.append(message(.user, "und in Deutschland?"))
        let text = FollowUpResolver.requestMessages(text: "und in Deutschland?", history: history).first?.text ?? ""
        XCTAssertTrue(text.hasPrefix("CONTEXT:\n"))
        XCTAssertTrue(text.contains("Nachricht 7"))
        XCTAssertTrue(text.contains("NEW QUESTION:\nund in Deutschland?"))
        XCTAssertFalse(text.contains("Nachricht 1"), "ältere Nachrichten fallen heraus")
        let contextLines = text.components(separatedBy: "\n")
            .filter { $0.hasPrefix("user:") || $0.hasPrefix("assistant:") }
        XCTAssertEqual(contextLines.count, ConversationTranscript.defaultLimit)
    }

    func testTheLatestAnswerStaysWholeAndOlderOnesAreCappedOnOneLine() {
        let history = [message(.user, "Erzähl was über Solarzellen"),
                       message(.assistant, String(repeating: "alt ", count: 300) + "ALTENDE"),
                       message(.user, "und Windkraft?"),
                       message(.assistant, String(repeating: "wort ", count: 500) + "\nZEILE2"),
                       message(.user, "und daraus?")]
        let text = FollowUpResolver.requestMessages(text: "und daraus?", history: history).first?.text ?? ""
        let answers = text.components(separatedBy: "\n").filter { $0.hasPrefix("assistant:") }
        XCTAssertEqual(answers.count, 2)
        XCTAssertFalse(answers[0].contains("ALTENDE"), "ältere Antworten bleiben gekappt")
        XCTAssertLessThanOrEqual(answers[0].count, ConversationTranscript.defaultCap + 20)
        XCTAssertTrue(answers[1].hasSuffix("ZEILE2"), "die letzte Antwort kommt ganz und auf einer Zeile mit")
        XCTAssertTrue(text.contains("und daraus?"))
    }

    func testOnlyAResolvedToolCallBecomesAStandaloneQuery() {
        let resolved = ToolCallPayload.call(ToolRouter.resolveQueryTool,
                                            ["status": "resolved",
                                             "query": "Hauptursachen der Klimaerwärmung in Deutschland"])
        XCTAssertEqual(FollowUpResolver.resolvedQuery(from: resolved),
                       "Hauptursachen der Klimaerwärmung in Deutschland")
        let unresolved = ToolCallPayload.call(ToolRouter.resolveQueryTool,
                                              ["status": "unresolved", "query": ""])
        XCTAssertNil(FollowUpResolver.resolvedQuery(from: unresolved))
        let empty = ToolCallPayload.call(ToolRouter.resolveQueryTool,
                                         ["status": "resolved", "query": "   "])
        XCTAssertNil(FollowUpResolver.resolvedQuery(from: empty))
        let foreign = payload(ToolRouter.searchTool, #"{"query":"Wetter"}"#)
        XCTAssertNil(FollowUpResolver.resolvedQuery(from: foreign))
    }

    func testALongResolvedQueryIsCapped() {
        let long = ToolCallPayload.call(ToolRouter.resolveQueryTool,
                                        ["status": "resolved", "query": String(repeating: "a", count: 400)])
        XCTAssertEqual(FollowUpResolver.resolvedQuery(from: long)?.count, FollowUpResolver.maxQueryChars)
    }

    func testUsabilityGateRejectsEverythingThatIsNotAQuery() {
        XCTAssertFalse(FollowUpResolver.isUsable("zu kurz", insteadOf: "und in Deutschland?"))
        XCTAssertFalse(FollowUpResolver.isUsable("und in Deutschland?", insteadOf: " und in Deutschland? "))
        XCTAssertFalse(FollowUpResolver.isUsable(String(repeating: "a", count: 300), insteadOf: "und in Deutschland?"))
        XCTAssertTrue(FollowUpResolver.isUsable("Hauptursachen der Klimaerwärmung in Deutschland",
                                                insteadOf: "und in Deutschland?"))
    }

    func testInstructionsDemandAStructuredStandaloneQuery() {
        let instructions = Prompt.Research.followUpQuery()
        XCTAssertTrue(instructions.contains("standalone search query"))
        XCTAssertTrue(instructions.contains(ToolRouter.resolveQueryTool))
        XCTAssertTrue(instructions.contains(StructuredToolStatus.resolved.rawValue))
        XCTAssertTrue(instructions.contains(StructuredToolStatus.unresolved.rawValue))
        XCTAssertTrue(instructions.contains("already self-contained, repeat it unchanged"))
        XCTAssertTrue(instructions.contains("[image attached]"))
        XCTAssertTrue(instructions.contains("[generated image]"))
        XCTAssertTrue(instructions.contains("that picture is on this request"),
                      "die Anweisung darf kein Bild leugnen, das inzwischen mitfährt")
        XCTAssertFalse(instructions.contains("{{"), instructions)
    }

}
