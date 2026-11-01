@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class RequestBuildingTests: GwenTestCase {
    private let baseURL = "https://token-plan.example/compatible-mode/v1"
    private let tinyJPEG = Data([0xFF, 0xD8, 0xFF, 0xD9])

    private func jsonObject(_ req: URLRequest) -> [String: Any] {
        (try? jsonData(of: req)) ?? [:]
    }

    private func messages(_ req: URLRequest) -> [[String: Any]] {
        (try? jsonMessages(of: req)) ?? []
    }

    func testTheFollowUpRequestCarriesThePictureTheQuestionPointsAt() throws {
        let plain = try QwenAPI.userRequest(baseURL: baseURL, key: "k", model: "m",
                                            text: "und in Polen?", picture: nil, thinking: .nothing)
        XCTAssertTrue(messages(plain).last?["content"] is String)
        XCTAssertEqual(messages(plain).count, 2)
        XCTAssertEqual(jsonObject(plain)["stream"] as? Bool, false)
        XCTAssertEqual(jsonObject(plain)["tool_choice"] as? String, ToolRouter.forcedChoice)
        let tools = try XCTUnwrap(jsonObject(plain)["tools"] as? [[String: Any]])
        let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        XCTAssertEqual(names, [ToolRouter.resolveQueryTool])

        let withPicture = try QwenAPI.userRequest(baseURL: baseURL, key: "k", model: "vision",
                                                  text: "und in Polen?", picture: tinyJPEG,
                                                  thinking: .nothing)
        let parts = try XCTUnwrap(messages(withPicture).last?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0]["text"] != nil)
        XCTAssertTrue(parts[1]["image_url"] != nil,
                      "die Rückfrage-Umschreibung braucht das Bild, sonst bleibt ein nacktes \"es\" stehen")
    }

    func testChatRequestCarriesModelStreamAndAuthHeaders() throws {
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "sk-test", model: "qwen3.8-flash",
                                          messages: [ChatMessage(role: .user, text: "hallo")],
                                          imageData: [], thinking: .nothing)
        XCTAssertEqual(req.url?.absoluteString, baseURL + "/chat/completions")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(req.timeoutInterval, APITimeout.chatRequest)
        XCTAssertEqual(jsonObject(req)["model"] as? String, "qwen3.8-flash")
        XCTAssertEqual(jsonObject(req)["stream"] as? Bool, true)
    }

    func testSystemMessageIsBuiltFromTheSinglePromptBuilder() throws {
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "m",
                                          messages: [ChatMessage(role: .user, text: "hi")],
                                          imageData: [], thinking: .nothing)
        let first = messages(req).first ?? [:]
        XCTAssertEqual(first["role"] as? String, "system")
        XCTAssertEqual(first["content"] as? String, SystemPrompt.chat())
    }

    func testExplicitSystemPromptOverridesTheDefaultOne() throws {
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "m",
                                          messages: [ChatMessage(role: .user, text: "hi")],
                                          imageData: [], system: "nur JSON", thinking: .nothing)
        XCTAssertEqual((messages(req).first ?? [:])["content"] as? String, "nur JSON")
    }

    func testPlainTextHistoryPartsAreStringsAndOrderIsPreserved() throws {
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "m",
                                          messages: [ChatMessage(role: .user, text: "frage"),
                                                     ChatMessage(role: .assistant, text: "antwort")],
                                          imageData: [], thinking: .nothing)
        let parts = messages(req).dropFirst().map { $0["content"] as? String }
        XCTAssertEqual(Array(parts), ["frage", "antwort"])
    }

    func testUserImagesBecomeDataURLPartsPairedWithUploadedBytes() throws {
        let attached = ChatMessage(role: .user, text: "beschreibe", images: [Attachment(file: "a.jpg")])
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "m",
                                          messages: [attached], imageData: [tinyJPEG], thinking: .nothing)
        let content = (messages(req)[1])["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[0]["text"] as? String, "beschreibe")
        let urlValue = ((content[1]["image_url"] as? [String: Any])?["url"] as? String) ?? ""
        XCTAssertTrue(urlValue.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertEqual(String(urlValue.dropFirst("data:image/jpeg;base64,".count)),
                       tinyJPEG.base64EncodedString())
    }

    func testEmptyUserTextFallsBackToDescribePrompt() throws {
        let attached = ChatMessage(role: .user, text: "", images: [Attachment(file: "a.jpg")])
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "m",
                                          messages: [attached], imageData: [tinyJPEG], thinking: .nothing)
        let content = (messages(req)[1])["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(content.first?["text"] as? String, L.t("describe_images"))
    }

    func testRememberedPictureTravelsWithTheNewestQuestion() throws {
        let history = [ChatMessage(role: .user, text: "Male einen Turm im Sturm"),
                       ChatMessage(role: .assistant, text: "Hier ist dein Turm.",
                                   outImages: [Attachment(file: "gen.jpg")]),
                       ChatMessage(role: .user, text: "Warum ist der Himmel dort grau?")]
        let turn = ConversationMemory.turn(from: history, load: { _ in tinyJPEG })
        XCTAssertTrue(turn.needsVision)
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "vision",
                                          messages: turn.messages, imageData: turn.images, thinking: .nothing)
        let content = try XCTUnwrap(messages(req).last?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, "Warum ist der Himmel dort grau?")
        let url = ((content.last?["image_url"] as? [String: Any])?["url"] as? String) ?? ""
        XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertEqual(String(url.dropFirst("data:image/jpeg;base64,".count)), tinyJPEG.base64EncodedString())
    }

    func testEveryCarriedImageHasItsOwnBytesInTheRequest() throws {
        let history = [ChatMessage(role: .user, text: "zwei bilder",
                                   images: [Attachment(file: "a.jpg"), Attachment(file: "b.jpg")]),
                       ChatMessage(role: .user, text: "noch eine frage")]
        let turn = ConversationMemory.turn(from: history) { $0.file == "a.jpg" ? tinyJPEG : nil }
        XCTAssertEqual(turn.images.count, 1)
        XCTAssertEqual(turn.messages.flatMap(\.images).count, turn.images.count)
    }

    func testTrailingSlashInBaseURLIsCollapsed() throws {
        let req = try QwenAPI.makeRequest(baseURL: baseURL + "/", key: "k", model: "m",
                                          messages: [ChatMessage(role: .user, text: "x")], imageData: [], thinking: .nothing)
        XCTAssertEqual(req.url?.absoluteString, baseURL + "/chat/completions")
    }

    func testUnparseableBaseURLThrowsLocalisedError() {
        XCTAssertThrowsError(try QwenAPI.makeRequest(baseURL: "http://%zz", key: "k", model: "m",
                                                     messages: [ChatMessage(role: .user, text: "x")],
                                                     imageData: [], thinking: .nothing)) { error in
            XCTAssertEqual((error as? APIError)?.message, L.t("bad_url"))
        }
    }

    func testAPathWithSpacesSurvivesWhileAStringWithoutHostIsRefused() {
        XCTAssertNoThrow(try QwenAPI.makeRequest(baseURL: "https://example.invalid/mein pfad/v1", key: "k",
                                                 model: "m", messages: [ChatMessage(role: .user, text: "x")],
                                                 imageData: [], thinking: .nothing))
        for unusable in ["not a url", "localhost:11434/v1", "   "] {
            XCTAssertThrowsError(try QwenAPI.makeRequest(baseURL: unusable, key: "k", model: "m",
                                                         messages: [ChatMessage(role: .user, text: "x")],
                                                         imageData: [], thinking: .nothing),
                                 "\(unusable) darf keine Anfrage ohne Ziel erzeugen") { error in
                XCTAssertEqual((error as? APIError)?.message, L.t("bad_url"))
            }
        }
    }

    func testImageRequestWrapsEditPromptInCompositionFrame() throws {
        let req = try QwenAPI.makeImageRequest(baseURL: baseURL, key: "k", model: "wan2.7-image",
                                              prompt: "heller machen", inputImages: [tinyJPEG], isEdit: true)
        XCTAssertEqual(req.timeoutInterval, APITimeout.imageRequest)
        let content = (messages(req).first ?? [:])["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(content.first?["image"] as? String, "data:image/jpeg;base64,\(tinyJPEG.base64EncodedString())")
        let text = content.last?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("heller machen"))
        XCTAssertTrue(text.hasPrefix(String(L.t("edit_frame").prefix(20))))
    }

    func testImageRequestWithSeveralPicturesUsesTheOrderedCompositionFrame() throws {
        let req = try QwenAPI.makeImageRequest(baseURL: baseURL, key: "k", model: "wan2.7-image",
                                              prompt: "übertrage die farbe", inputImages: [tinyJPEG, tinyJPEG],
                                              isEdit: true)
        let content = (messages(req).first ?? [:])["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(content.count, 3)
        XCTAssertEqual(content.first?["image"] as? String,
                       "data:image/jpeg;base64,\(tinyJPEG.base64EncodedString())")
        let text = content.last?["text"] as? String ?? ""
        XCTAssertTrue(text.hasPrefix(String(L.t("edit_frame_multi").prefix(20))))
        XCTAssertTrue(text.contains("übertrage die farbe"))
    }

    func testImageRequestWithoutInputImagesSendsPlainText() throws {
        let req = try QwenAPI.makeImageRequest(baseURL: baseURL, key: "k", model: "m",
                                              prompt: "eine katze", inputImages: [], isEdit: false)
        let content = (messages(req).first ?? [:])["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content.first?["text"] as? String, "eine katze")
    }

    func testModelsRequestIsAuthorizedGet() throws {
        let req = try QwenAPI.fetchModelsRequest(baseURL: baseURL, key: "sk-x")
        XCTAssertEqual(req.url?.absoluteString, baseURL + "/models")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-x")
        XCTAssertEqual(req.timeoutInterval, APITimeout.modelsRequest)
    }

    func testChatRequestWithoutThinkingChoiceSendsNoThinkingKeys() throws {
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "qwen3.8-flash",
                                          messages: [ChatMessage(role: .user, text: "hi")],
                                          imageData: [], thinking: .nothing)
        let body = jsonObject(req)
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertNil(body["enable_thinking"])
        XCTAssertNil(body["thinking_budget"])
    }

    func testChatRequestCarriesExactlyOneThinkingKey() throws {
        let levelled = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "qwen3.8-flash",
                                               messages: [ChatMessage(role: .user, text: "hi")],
                                               imageData: [], thinking: .effort(.medium))
        XCTAssertEqual(jsonObject(levelled)["reasoning_effort"] as? String, "medium")
        XCTAssertNil(jsonObject(levelled)["enable_thinking"])
        let off = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "deepseek-v4-pro",
                                          messages: [ChatMessage(role: .user, text: "hi")],
                                          imageData: [], thinking: .suppressing(.dashScope))
        XCTAssertEqual(jsonObject(off)["enable_thinking"] as? Bool, false)
        XCTAssertNil(jsonObject(off)["reasoning_effort"])
    }

    func testWebAnswerRequestUsesTheSharedChatEndpoint() throws {
        let hits = [WebHit(title: "Quelle", url: "https://a.example", domain: "a.example", text: "text")]
        let req = try WebSearch.makeAnswerRequest(baseURL: baseURL, key: "k", model: "m",
                                                 question: "frage", hits: hits, thinking: .nothing)
        XCTAssertEqual(req.url?.absoluteString, baseURL + "/chat/completions")
        XCTAssertEqual(req.timeoutInterval, APITimeout.researchRequest)
        let content = (messages(req).last ?? [:])["content"] as? String ?? ""
        XCTAssertTrue(content.contains("## SOURCE [1]"))
        XCTAssertTrue(content.hasSuffix("frage"))
    }

    func testWebAnswerRequestCarriesTheDepthOfTheVisibleAnswer() throws {
        let hits = [WebHit(title: "Quelle", url: "https://a.example", domain: "a.example", text: "text")]
        let levelled = try WebSearch.makeAnswerRequest(baseURL: baseURL, key: "k", model: "m",
                                                      question: "frage", hits: hits,
                                                      thinking: .effort(.medium))
        XCTAssertEqual(jsonObject(levelled)["reasoning_effort"] as? String, "medium")
        XCTAssertNil(jsonObject(levelled)["enable_thinking"])
        let off = try WebSearch.makeAnswerRequest(baseURL: baseURL, key: "k", model: "m",
                                                 question: "frage", hits: hits,
                                                 thinking: .suppressing(.dashScope))
        XCTAssertEqual(jsonObject(off)["enable_thinking"] as? Bool, false)
        XCTAssertNil(jsonObject(off)["reasoning_effort"])
    }

    func testEveryRequestBuilderSendsItsThinkingDirectiveThroughTheSharedSeam() throws {
        let builders: [[String: Any]] = [
            try jsonObject(QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "m",
                                               messages: [ChatMessage(role: .user, text: "x")],
                                               imageData: [], thinking: .effort(.low))),
            try jsonObject(PictureDirector.request(baseURL: baseURL, key: "k", model: "m",
                                                   instruction: "x", pictures: [tinyJPEG],
                                                   thinking: .effort(.low))),
            try jsonObject(ToolRouter.request(baseURL: baseURL, key: "k", model: "m", text: "x",
                                              system: "s", attachable: false, thinking: .effort(.low))),
            try jsonObject(WebSearch.makeAnswerRequest(baseURL: baseURL, key: "k", model: "m",
                                                       question: "x", hits: [], thinking: .effort(.low))),
            try jsonObject(QwenAPI.userRequest(baseURL: baseURL, key: "k", model: "m", text: "x",
                                               picture: tinyJPEG, thinking: .effort(.low))),
            try jsonObject(VisionProductScanner.makeRequest(baseURL: baseURL, key: "k", model: "m",
                                                            question: "x", image: tinyJPEG,
                                                            thinking: .effort(.low))),
        ]
        XCTAssertEqual(builders.count, 6)
        for body in builders {
            XCTAssertEqual(body["reasoning_effort"] as? String, "low", String(describing: body))
            XCTAssertNil(body["enable_thinking"], String(describing: body))
            XCTAssertNotNil(body["messages"], String(describing: body))
        }
    }
}
