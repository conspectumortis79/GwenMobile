import XCTest
@testable import GwenMobile

final class ImagePromptComposerTests: XCTestCase {
    private var history: [ChatMessage] {
        [ChatMessage(role: .user, text: "Wie viele Einwohner hat Deutschland?"),
         ChatMessage(role: .assistant, text: "2024 waren es 84,7 Millionen Menschen."),
         ChatMessage(role: .user, text: "mach daraus ein bild")]
    }

    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    func testRequestsThatPointAtTheConversationAskForIt() {
        for text in ["mach daraus ein bild", "erzeuge ein bild aus diesen informationen",
                     "male das nochmal, aber bei nacht", "deine antwort als poster",
                     "zeichne die zahlen aus der tabelle", "generate a picture of that",
                     "mal das diagramm als linie"] {
            XCTAssertTrue(ImagePromptComposer.needsConversationContext(text, history: history), text)
        }
    }

    func testSelfContainedRequestsAreSentWithoutAnExtraCall() {
        for text in ["Erzeuge ein Bild von einem roten Drachen über einer Stadt",
                     "Generate a picture of a lighthouse on a cliff at dawn",
                     "Male einen Leuchtturm im Sturm bei Nacht"] {
            XCTAssertFalse(ImagePromptComposer.needsConversationContext(text, history: history), text)
        }
    }

    func testAFirstMessageHasNoConversationToRemember() {
        let empty: [ChatMessage] = [ChatMessage(role: .user, text: "mach daraus ein bild")]
        XCTAssertFalse(ImagePromptComposer.needsConversationContext("mach daraus ein bild", history: empty))
        XCTAssertFalse(ImagePromptComposer.needsConversationContext("mach daraus ein bild", history: []))
    }

    func testUsablePromptCleansWhatTheModelHandedBack() {
        XCTAssertEqual(ImagePromptComposer.usablePrompt("Ein Leuchtturm im Sturm, Ölgemälde",
                                                        insteadOf: "mach daraus ein bild"),
                       "Ein Leuchtturm im Sturm, Ölgemälde")
        XCTAssertEqual(ImagePromptComposer.usablePrompt("  \"Ein Leuchtturm im Sturm\"  ",
                                                        insteadOf: "mach daraus ein bild"),
                       "Ein Leuchtturm im Sturm")
        XCTAssertEqual(ImagePromptComposer.usablePrompt("```text\nEin Leuchtturm\nim Sturm\n```",
                                                        insteadOf: "male das"),
                       "Ein Leuchtturm im Sturm")
        XCTAssertEqual(ImagePromptComposer.usablePrompt("```Ein Leuchtturm im Sturm, Ölgemälde```",
                                                        insteadOf: "male das"),
                       "Ein Leuchtturm im Sturm, Ölgemälde")
    }

    func testUsablePromptRejectsEverythingThatIsNotAPrompt() {
        XCTAssertNil(ImagePromptComposer.usablePrompt("zu kurz", insteadOf: "mach daraus ein bild"))
        XCTAssertNil(ImagePromptComposer.usablePrompt("Das kann ich nicht beantworten.",
                                                      insteadOf: "mach daraus ein bild"))
        XCTAssertNil(ImagePromptComposer.usablePrompt("Unable to help", insteadOf: "mach daraus ein bild"))
        XCTAssertNil(ImagePromptComposer.usablePrompt("mach daraus ein bild", insteadOf: "mach daraus ein bild"))
        XCTAssertNil(ImagePromptComposer.usablePrompt("   ", insteadOf: "mach daraus ein bild"))
        let long = String(repeating: "wort ", count: 300)
        XCTAssertEqual(ImagePromptComposer.usablePrompt(long, insteadOf: "mach daraus ein bild")?.count,
                       ImagePromptComposer.maxPromptChars)
    }

    func testRequestMessagesCarryTheAnswerInTheContext() {
        let messages = ImagePromptComposer.requestMessages(text: "mach daraus ein bild", history: history)
        XCTAssertEqual(messages.count, 1)
        let text = messages.first?.text ?? ""
        XCTAssertTrue(text.contains("KONTEXT:"))
        XCTAssertTrue(text.contains("84,7 Millionen"))
        XCTAssertTrue(text.hasSuffix("NEUE FRAGE:\nmach daraus ein bild"))
    }

    func testInstructionsDemandASelfContainedPictureDescription() {
        let instructions = Prompt.Research.imagePrompt(pictures: 1)
        XCTAssertTrue(instructions.contains("ONLY the prompt text"))
        XCTAssertTrue(instructions.contains("never sees the conversation"))
        XCTAssertTrue(instructions.contains("davon"))
        XCTAssertTrue(instructions.contains("repeat it unchanged"))
    }

    func testInstructionsNameTheTargetPictureByItsNumberWhenSeveralPicturesComeAlong() {
        let single = Prompt.Research.imagePrompt(pictures: 1)
        let several = Prompt.Research.imagePrompt(pictures: 3)
        XCTAssertFalse(single.contains("numbered from 1 (the oldest)"))
        XCTAssertTrue(several.contains("numbered from 1 (the oldest) to 3 (the newest)"))
        XCTAssertTrue(several.contains("Name the picture that must be edited by that number"))
    }
}
