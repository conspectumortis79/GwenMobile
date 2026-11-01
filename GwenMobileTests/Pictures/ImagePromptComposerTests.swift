@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ImagePromptComposerTests: GwenTestCase {
    private var history: [ChatMessage] {
        [ChatMessage(role: .user, text: "Wie viele Einwohner hat Deutschland?"),
         ChatMessage(role: .assistant, text: "2024 waren es 84,7 Millionen Menschen."),
         ChatMessage(role: .user, text: "mach daraus ein bild")]
    }

    func testOnlyAResolvedToolCallCarriesThePrompt() {
        let resolved = ToolCallPayload.call(ToolRouter.composeImagePromptTool,
                                            ["status": "resolved",
                                             "prompt": "Ein Leuchtturm im Sturm, Ölgemälde"])
        XCTAssertEqual(ImagePromptComposer.prompt(from: resolved), "Ein Leuchtturm im Sturm, Ölgemälde")
        let unresolved = ToolCallPayload.call(ToolRouter.composeImagePromptTool,
                                              ["status": "unresolved", "prompt": ""])
        XCTAssertNil(ImagePromptComposer.prompt(from: unresolved))
        let empty = ToolCallPayload.call(ToolRouter.composeImagePromptTool,
                                         ["status": "resolved", "prompt": "   "])
        XCTAssertNil(ImagePromptComposer.prompt(from: empty))
        let foreign = payload(ToolRouter.createTool, #"{"prompt":"Ein Leuchtturm"}"#)
        XCTAssertNil(ImagePromptComposer.prompt(from: foreign))
    }

    func testUsablePromptRejectsEverythingThatIsNotAPrompt() {
        XCTAssertNil(ImagePromptComposer.usablePrompt(nil, insteadOf: "mach daraus ein bild"))
        XCTAssertNil(ImagePromptComposer.usablePrompt("zu kurz", insteadOf: "mach daraus ein bild"))
        XCTAssertNil(ImagePromptComposer.usablePrompt("mach daraus ein bild", insteadOf: "mach daraus ein bild"))
        XCTAssertNil(ImagePromptComposer.usablePrompt("   ", insteadOf: "mach daraus ein bild"))
        let long = String(repeating: "wort ", count: 300)
        XCTAssertEqual(ImagePromptComposer.usablePrompt(long, insteadOf: "mach daraus ein bild")?.count,
                       ImagePromptComposer.maxPromptChars)
    }

    func testTheImagePromptRequestForcesThePromptTool() throws {
        let request = try QwenAPI.composeImagePromptRequest(baseURL: "https://q.test/v1", key: "k",
                                                            model: "m", instruction: "mach daraus ein bild",
                                                            history: history, pictures: 1, thinking: .nothing)
        let body = try XCTUnwrap(jsonBody(of: request))
        XCTAssertEqual(body["tool_choice"] as? String, ToolRouter.forcedChoice)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        XCTAssertEqual(names, [ToolRouter.composeImagePromptTool])
    }

    func testRequestMessagesCarryTheAnswerInTheContext() {
        let messages = ImagePromptComposer.requestMessages(text: "mach daraus ein bild", history: history)
        XCTAssertEqual(messages.count, 1)
        let text = messages.first?.text ?? ""
        XCTAssertTrue(text.contains("CONTEXT:"))
        XCTAssertTrue(text.contains("84,7 Millionen"))
        XCTAssertTrue(text.hasSuffix("NEW QUESTION:\nmach daraus ein bild"))
    }

    func testInstructionsDemandASelfContainedPictureDescription() {
        let instructions = Prompt.Research.imagePrompt(pictures: 1)
        XCTAssertTrue(instructions.contains(ToolRouter.composeImagePromptTool))
        XCTAssertTrue(instructions.contains(StructuredToolStatus.resolved.rawValue))
        XCTAssertTrue(instructions.contains(StructuredToolStatus.unresolved.rawValue))
        XCTAssertTrue(instructions.contains("never sees the conversation"))
        XCTAssertTrue(instructions.contains("make a picture out of it"))
        XCTAssertTrue(instructions.contains("repeat it unchanged"))
        XCTAssertFalse(instructions.contains("{{"), instructions)
    }

    func testInstructionsNameTheTargetPictureByItsNumberWhenSeveralPicturesComeAlong() {
        let single = Prompt.Research.imagePrompt(pictures: 1)
        let several = Prompt.Research.imagePrompt(pictures: 3)
        XCTAssertFalse(single.contains("numbered from 1 (the oldest)"))
        XCTAssertTrue(several.contains("numbered from 1 (the oldest) to 3 (the newest)"))
        XCTAssertTrue(several.contains("Name the picture that must be edited by that number"))
    }
}
