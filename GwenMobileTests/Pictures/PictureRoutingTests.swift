@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class PictureRoutingTests: GwenTestCase {
    private func tool(_ name: String, _ tools: [[String: Any]] = ToolRouter.tools(attachable: false)) -> [String: Any]? {
        tools.first { ($0["function"] as? [String: Any])?["name"] as? String == name }?["function"] as? [String: Any]
    }

    func testAWishForExistingPhotosTakesThePictureSearchRoute() {
        let decision = ToolRouter.map(name: ToolRouter.findTool, arguments: #"{"query":"cary elwes"}"#)
        XCTAssertEqual(decision?.route, .pictureSearch(query: "cary elwes"))
        XCTAssertEqual(decision?.pictureQuery, "cary elwes")
        XCTAssertNil(decision?.picturePrompt, "die Bildersuche darf dem Generator nichts übergeben")
        XCTAssertNil(decision?.searchQuery, "die Bildersuche darf nicht die Textsuche starten")
    }

    func testTheSearchRouteIsItsOwnCaseBesideTheGenerator() {
        XCTAssertNotEqual(SendRoute.pictureSearch(query: "a"), SendRoute.imageCreate)
        XCTAssertNotEqual(SendRoute.pictureSearch(query: "a"), SendRoute.chat)
        XCTAssertEqual(SendRoute.pictureSearch(query: "a"), SendRoute.pictureSearch(query: "a"))
    }

    func testAToolCallWithoutWordsFallsBackToPlainChat() {
        XCTAssertEqual(ToolRouter.map(name: ToolRouter.findTool, arguments: "{}")?.route, .chat)
        XCTAssertNil(ToolRouter.map(name: ToolRouter.findTool, arguments: #"{"query":"   "}"#)?.pictureQuery)
    }

    func testTheRouterReadsTheAnswerOfTheModelAndKeepsThePictureQuestion() throws {
        let body: [String: Any] = ["choices": [["message": ["tool_calls": [[
            "id": "1", "type": "function",
            "function": ["name": ToolRouter.findTool,
                         "arguments": #"{"query":"fotos vom nordlicht"}"#],
        ]]]]]]
        let data = try JSONSerialization.data(withJSONObject: body)
        let decision = try XCTUnwrap(ToolRouter.decisions(from: data).first)
        XCTAssertEqual(decision.route, .pictureSearch(query: "fotos vom nordlicht"))
    }

    func testTheFoundPictureToolExplainsThatItDrawsNothing() throws {
        let description = try XCTUnwrap(tool(ToolRouter.findTool)?["description"] as? String)
        XCTAssertTrue(description.contains("already exist"), description)
        XCTAssertTrue(description.contains(ToolRouter.createTool), description)
        XCTAssertTrue(description.contains(ToolRouter.editTool), description)
        let parameters = try XCTUnwrap(tool(ToolRouter.findTool)?["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertNotNil(properties["query"])
    }

    func testTheGeneratorIsPointedAtTheSearchForExistingPhotos() throws {
        let created = try XCTUnwrap(tool(ToolRouter.createTool)?["description"] as? String)
        XCTAssertTrue(created.contains(ToolRouter.findTool),
                      "ohne den Verweis holt 'zeig mir fotos von …' das Bildmodell")
    }

    func testThePolicySeparatesFoundPicturesFromInventedOnes() {
        let block = ToolRouter.systemBlock(now: "2026-09-23", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains(ToolRouter.findTool), block)
        XCTAssertTrue(block.contains("already exist"), block)
        XCTAssertTrue(block.contains("neither \(ToolRouter.createTool)"), block)
    }

    func testTheFlowTraceNamesThePictureQuestion() {
        let decision = ToolDecision(route: .pictureSearch(query: "hoodini"), pictureQuery: "hoodini")
        XCTAssertTrue(ChatView.sendTrace(decision: decision).contains("bildsuchtext=hoodini"),
                      ChatView.sendTrace(decision: decision))
    }

    func testThePictureSearchNeedsNoImageModel() {
        let offered = ToolRouter.tools(attachable: false).compactMap {
            ($0["function"] as? [String: Any])?["name"] as? String
        }
        XCTAssertTrue(offered.contains(ToolRouter.findTool))
        XCTAssertFalse(offered.contains(ToolRouter.editTool),
                       "ohne Bild auf dem Schirm gibt es nichts zu bearbeiten")
    }

    func testTheFoundPictureToolPointsBackAtThePictureAlreadyShown() throws {
        let description = try XCTUnwrap(tool(ToolRouter.findTool)?["description"] as? String)
        XCTAssertTrue(description.contains("attached to this message"), description)
        XCTAssertTrue(description.contains(ToolRouter.answerTool), description)
    }

    func testAMakeWishAboutARealSubjectIsWiredToTheGenerator() throws {
        let finder = try XCTUnwrap(tool(ToolRouter.findTool)?["description"] as? String)
        XCTAssertTrue(finder.contains("make, draw"), finder)
        XCTAssertTrue(finder.contains(ToolRouter.createTool), finder)
        let creator = try XCTUnwrap(tool(ToolRouter.createTool)?["description"] as? String)
        XCTAssertTrue(creator.contains("the subject really exists"), creator)
        XCTAssertTrue(creator.contains(ToolRouter.findTool), creator)
        let block = ToolRouter.systemBlock(now: "2026-09-23", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains("is create_picture even when its subject really exists"), block)
        XCTAssertTrue(block.contains("never find_pictures"), block)
    }

    func testAQuestionAboutThePictureInTheChatIsAnsweredByTheRouterText() {
        let attached = ToolRouter.systemBlock(now: "2026-09-23",
                                              context: SendContext(attachedImage: true), transcript: "")
        XCTAssertTrue(attached.contains("attached a new picture"), attached)
        XCTAssertTrue(attached.contains("a question about it is \(ToolRouter.answerTool)"), attached)
        XCTAssertTrue(attached.contains("never \(ToolRouter.findTool)"), attached)
        let remembered = ToolRouter.systemBlock(now: "2026-09-23",
                                                context: SendContext(rememberedImage: true), transcript: "")
        XCTAssertTrue(remembered.contains("still on screen"), remembered)
        XCTAssertTrue(remembered.contains("a question about it is \(ToolRouter.answerTool)"), remembered)
        XCTAssertTrue(remembered.contains("never \(ToolRouter.findTool)"), remembered)
    }

    func testAChangeToAnEarlierPictureOfTheChatIsAnEditEvenWhenTheNewestShowsSomethingElse() {
        let remembered = ToolRouter.systemBlock(now: "2026-09-23",
                                                context: SendContext(rememberedImage: true), transcript: "")
        XCTAssertTrue(remembered.contains("The pictures of this chat are sent along, oldest first"), remembered)
        XCTAssertTrue(remembered.contains("A wish to change any picture of the chat"), remembered)
        XCTAssertTrue(remembered.contains("is \(ToolRouter.editTool), also when the newest picture does not show "
                                          + "what the wish names"), remembered)
        for context in [SendContext(), SendContext(attachedImage: true)] {
            let other = ToolRouter.systemBlock(now: "2026-09-23", context: context, transcript: "")
            XCTAssertFalse(other.contains("The pictures of this chat are sent along, oldest first"), other)
        }
    }

    func testThePolicyNamesThePictureAlreadyInPlayAsNothingToLookUp() {
        let block = ToolRouter.systemBlock(now: "2026-09-23", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains("A picture the user attached or still sees in the chat"), block)
        XCTAssertTrue(block.contains("is \(ToolRouter.answerTool)"), block)
    }

    func testAQuestionAboutTheShownPictureReachesTheRouterLikeEveryOtherWish() {
        XCTAssertFalse(ToolRouter.carriesOnlyPictures(text: "Was ist auf dem Foto?", pictures: 1))
        XCTAssertFalse(ToolRouter.carriesOnlyPictures(text: "Mache das Bild etwas heller", pictures: 1))
        XCTAssertFalse(ToolRouter.carriesOnlyPictures(text: "finde mir alle bilder von cary elwes",
                                                      pictures: 1))
    }

    func testTheModelAnswerAboutThePictureBecomesPlainChat() throws {
        let body: [String: Any] = ["choices": [["message": ["tool_calls": [[
            "id": "1", "type": "function",
            "function": ["name": ToolRouter.answerTool, "arguments": "{}"],
        ]]]]]]
        let data = try JSONSerialization.data(withJSONObject: body)
        XCTAssertEqual(try XCTUnwrap(ToolRouter.decisions(from: data).first).route, .chat)
    }
}
