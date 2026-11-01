@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

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

    func testNamedPictureThatFitsNoShownPictureIsReportedInsteadOfGuessed() {
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

    func testNumbersOutsideTheIndexRangeAreRejectedInsteadOfTrapping() {
        XCTAssertNil(PictureDirector.number(NSNumber(value: 1e300)))
        XCTAssertNil(PictureDirector.number(NSNumber(value: -1e300)))
        XCTAssertNil(PictureDirector.number(NSNumber(value: Double.infinity)))
        XCTAssertNil(PictureDirector.number(NSNumber(value: Double.nan)))
        XCTAssertNil(PictureDirector.direction(from: #"{"edit":1e300,"instruction":"x"}"#, pictures: 3))
        XCTAssertNil(PictureDirector.direction(from: #"{"edit":-1e300,"instruction":"x"}"#, pictures: 3))
        XCTAssertEqual(PictureDirector.number(NSNumber(value: 2.9)), 2)
        XCTAssertEqual(PictureDirector.number(NSNumber(value: -1.5)), -1)
        XCTAssertEqual(PictureDirector.number(" 3 "), 3)
        XCTAssertNil(PictureDirector.number("zwei"))
    }

    func testOnlyTheTargetPictureGoesToTheGenerator() {
        let images = [one, two, three]
        XCTAssertEqual(PictureDirection.edit(target: 3, reference: 1, instruction: "x").pictures(from: images),
                       [three])
        XCTAssertEqual(PictureDirection.edit(target: 2, reference: nil, instruction: "x").pictures(from: images),
                       [two])
        XCTAssertNil(PictureDirection.unreachable.pictures(from: images))
    }

    func testInstructionsSendTheDirectorToMatchPicturesByDescription() {
        let instructions = Prompt.Pictures.director(pictures: 3)
        XCTAssertTrue(instructions.contains("and never by counting"))
        XCTAssertTrue(instructions.contains("answer {\"edit\":null}"))
        XCTAssertTrue(instructions.contains("does not need the template in front of it"))
        XCTAssertTrue(instructions.contains("what must stay exactly as it is in the target image"))
        XCTAssertTrue(instructions.contains("never use picture numbers"))
        XCTAssertTrue(instructions.contains("just sent by the user"))
        XCTAssertTrue(instructions.contains("only the size of the target's own object changes"))
        XCTAssertFalse(instructions.contains("chat place"))
        XCTAssertFalse(instructions.contains("ordinal"))
        XCTAssertFalse(instructions.contains("HINWEIS DES PROGRAMMS"))
    }

    func testLabelsNumberTheShownPicturesAndMarkTheFreshOnes() {
        XCTAssertEqual(PictureDirector.label(number: 1, fresh: []), "IMAGE 1")
        XCTAssertEqual(PictureDirector.label(number: 2, fresh: [2]), "IMAGE 2 (just sent by the user)")
        XCTAssertEqual(PictureDirector.label(number: 9, fresh: []), "IMAGE 9")
    }

    func testFreshPicturesAreLabelledSoTheDirectorCanTellThemApart() throws {
        let req = try PictureDirector.request(baseURL: "https://example.test/compatible-mode/v1",
                                              key: "sk-test", model: "qwen3.8-max",
                                              instruction: "übertrage die farbe",
                                              pictures: [one, two], fresh: [2], thinking: .nothing)
        let content = try XCTUnwrap(((self.jsonBody(of: req)?["messages"] as? [[String: Any]])?
            .first?["content"] as? [[String: Any]]))
        XCTAssertEqual(content.count, 5)
        let text = (content.first?["text"] as? String) ?? ""
        XCTAssertTrue(text.contains("REQUEST: übertrage die farbe"))
        XCTAssertEqual(content[1]["text"] as? String, "IMAGE 1")
        XCTAssertEqual(((content[2]["image_url"] as? [String: Any])?["url"] as? String) ?? "",
                       "data:image/jpeg;base64,\(one.base64EncodedString())")
        XCTAssertEqual(content[3]["text"] as? String, "IMAGE 2 (just sent by the user)")
    }

    func testAnOversizedPictureIsRejectedBeforeTheDirectorRequest() {
        let oversized = Data(repeating: 0xAB, count: ImagePolicy.uploadByteBudget + 1)
        XCTAssertThrowsError(try PictureDirector.request(baseURL: "https://example.test/compatible-mode/v1",
                                                         key: "k", model: "m", instruction: "x",
                                                         pictures: [oversized], thinking: .nothing))
    }

    func testRequestSendsNoThinkingKeysAndTheChatCompletionsEndpoint() throws {
        let req = try PictureDirector.request(baseURL: "https://example.test/compatible-mode/v1",
                                              key: "sk-test", model: "qwen3.8-max",
                                              instruction: "x", pictures: [one, two], thinking: .nothing)
        let body = try XCTUnwrap(self.jsonBody(of: req))
        XCTAssertEqual(body["model"] as? String, "qwen3.8-max")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["temperature"] as? Double, 0)
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertNil(body["enable_thinking"])
        XCTAssertEqual(req.url?.path, "/compatible-mode/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }
}
