import XCTest
@testable import GwenMobile

final class PictureDirectorTests: XCTestCase {
    private let one = Data([1, 1])
    private let two = Data([2, 2])
    private let three = Data([3, 3])

    func testDirectionComesOutOfTheProviderSentence() {
        let raw = #"Text davor {"edit":3,"reference":1,"instruction":"Male das Zielbild in der Farbe der Vorlage."} Text danach"#
        XCTAssertEqual(PictureDirector.direction(from: raw, pictures: 3),
                       .edit(target: 3, reference: 1,
                             instruction: "Male das Zielbild in der Farbe der Vorlage."))
    }

    func testReferenceIsDroppedWhenUseless() {
        XCTAssertEqual(PictureDirector.direction(from: #"{"edit":1,"reference":null,"instruction":"heller machen"}"#,
                                                 pictures: 2),
                       .edit(target: 1, reference: nil, instruction: "heller machen"))
        XCTAssertEqual(PictureDirector.direction(from: #"{"edit":2,"reference":2,"instruction":"x"}"#,
                                                 pictures: 3),
                       .edit(target: 2, reference: nil, instruction: "x"))
    }

    func testNamedPictureOutOfReachIsReportedInsteadOfGuessed() {
        XCTAssertEqual(PictureDirector.direction(from: #"{"edit":null,"instruction":""}"#, pictures: 4),
                       .unreachable)
        XCTAssertNil(PictureDirector.direction(from: #"{"instruction":"x"}"#, pictures: 4))
    }

    func testTargetOutsideThePickedPicturesIsRejected() {
        XCTAssertNil(PictureDirector.direction(from: #"{"edit":5,"instruction":"x"}"#, pictures: 3))
        XCTAssertNil(PictureDirector.direction(from: #"{"edit":0,"instruction":"x"}"#, pictures: 3))
        XCTAssertNil(PictureDirector.direction(from: "kein json", pictures: 3))
    }

    func testEmptyInstructionAndSinglePictureSelectionAreNoDirection() {
        XCTAssertNil(PictureDirector.direction(from: #"{"edit":1,"instruction":"   "}"#, pictures: 3))
        XCTAssertNil(PictureDirector.direction(from: #"{"edit":1,"instruction":"x"}"#, pictures: 1))
    }

    func testIndexesAlsoArriveAsTextOrDecimals() {
        XCTAssertEqual(PictureDirector.direction(from: #"{ "edit" : "3" , "reference": 1.0, "instruction":"x"}"#,
                                                 pictures: 3),
                       .edit(target: 3, reference: 1, instruction: "x"))
        XCTAssertNil(PictureDirector.direction(from: #"{"edit":"zwei","instruction":"x"}"#, pictures: 3))
    }

    func testOnlyTheTargetPictureGoesToTheGenerator() {
        let images = [one, two, three]
        XCTAssertEqual(PictureDirection.edit(target: 3, reference: 1, instruction: "x").pictures(from: images),
                       [three])
        XCTAssertEqual(PictureDirection.edit(target: 2, reference: nil, instruction: "x").pictures(from: images),
                       [two])
        XCTAssertNil(PictureDirection.unreachable.pictures(from: images))
    }

    func testInstructionsTellTheDirectorWhichChatPlacesAreShown() {
        let instructions = PictureDirector.instructions(pictures: 3, shown: [1, 3, 4], total: 5)
        XCTAssertTrue(instructions.contains("are 1, 3, 4 of 5 pictures"))
        XCTAssertTrue(instructions.contains("the chat's very first picture is BILD 1"))
        XCTAssertTrue(instructions.contains("answer {\"edit\":null}"))
        XCTAssertTrue(instructions.contains("does not need the template in front of it"))
        XCTAssertTrue(instructions.contains("what must stay exactly as it is in the target image"))
        XCTAssertTrue(instructions.contains("never use picture numbers"))
        XCTAssertTrue(instructions.contains("just sent by the user"))
        XCTAssertTrue(instructions.contains("Every BILD label also carries its place inside the chat"))
        XCTAssertTrue(instructions.contains("counts the pictures of the whole chat"))
        XCTAssertTrue(instructions.contains("only the size of the target's own object changes"))
    }

    func testLabelsCarryTheChatPlaceOfEveryShownPicture() {
        XCTAssertEqual(PictureDirector.label(number: 1, shown: [2, 3], fresh: []), "BILD 1 (chat position 2)")
        XCTAssertEqual(PictureDirector.label(number: 2, shown: [2, 3], fresh: [2]),
                       "BILD 2 (chat position 3) (just sent by the user)")
        XCTAssertEqual(PictureDirector.label(number: 9, shown: [2, 3], fresh: []), "BILD 9")
    }

    func testFreshPicturesAreLabelledSoTheDirectorCanTellThemApart() throws {
        let req = try PictureDirector.request(baseURL: "https://example.test/compatible-mode/v1",
                                              key: "sk-test", model: "qwen3.8-max",
                                              instruction: "übertrage die farbe",
                                              pictures: [one, two], shown: [2, 3], total: 3, fresh: [2])
        let content = try XCTUnwrap(((self.jsonBody(of: req)?["messages"] as? [[String: Any]])?
            .first?["content"] as? [[String: Any]]))
        XCTAssertEqual(content.count, 5)
        let text = (content.first?["text"] as? String) ?? ""
        XCTAssertTrue(text.contains("ANFRAGE: übertrage die farbe"))
        XCTAssertEqual(content[1]["text"] as? String, "BILD 1 (chat position 2)")
        XCTAssertEqual(((content[2]["image_url"] as? [String: Any])?["url"] as? String) ?? "",
                       "data:image/jpeg;base64,\(one.base64EncodedString())")
        XCTAssertEqual(content[3]["text"] as? String, "BILD 2 (chat position 3) (just sent by the user)")
    }

    func testRequestSendsNoThinkingKeysAndTheChatCompletionsEndpoint() throws {
        let req = try PictureDirector.request(baseURL: "https://example.test/compatible-mode/v1",
                                              key: "sk-test", model: "qwen3.8-max",
                                              instruction: "x", pictures: [one, two])
        let body = try XCTUnwrap(self.jsonBody(of: req))
        XCTAssertEqual(body["model"] as? String, "qwen3.8-max")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertNil(body["enable_thinking"])
        XCTAssertEqual(req.url?.path, "/compatible-mode/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }
}
