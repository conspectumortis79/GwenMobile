import XCTest
@testable import GwenMobile

@MainActor
final class RequestBuildingTests: XCTestCase {
    private let baseURL = "https://token-plan.example/compatible-mode/v1"
    private let tinyJPEG = Data([0xFF, 0xD8, 0xFF, 0xD9])

    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    private func jsonObject(_ req: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    private func messages(_ req: URLRequest) -> [[String: Any]] {
        jsonObject(req)["messages"] as? [[String: Any]] ?? []
    }

    func testChatRequestCarriesModelStreamAndAuthHeaders() throws {
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "sk-test", model: "qwen3.8-flash",
                                          messages: [ChatMessage(role: .user, text: "hallo")],
                                          imageData: [])
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
                                          imageData: [])
        let first = messages(req).first ?? [:]
        XCTAssertEqual(first["role"] as? String, "system")
        XCTAssertEqual(first["content"] as? String, SystemPrompt.chat())
    }

    func testExplicitSystemPromptOverridesTheDefaultOne() throws {
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "m",
                                          messages: [ChatMessage(role: .user, text: "hi")],
                                          imageData: [], system: "nur JSON")
        XCTAssertEqual((messages(req).first ?? [:])["content"] as? String, "nur JSON")
    }

    func testPlainTextHistoryPartsAreStringsAndOrderIsPreserved() throws {
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "m",
                                          messages: [ChatMessage(role: .user, text: "frage"),
                                                     ChatMessage(role: .assistant, text: "antwort")],
                                          imageData: [])
        let parts = messages(req).dropFirst().map { $0["content"] as? String }
        XCTAssertEqual(Array(parts), ["frage", "antwort"])
    }

    func testUserImagesBecomeDataURLPartsPairedWithUploadedBytes() throws {
        let attached = ChatMessage(role: .user, text: "beschreibe", images: [Attachment(file: "a.jpg")])
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "m",
                                          messages: [attached], imageData: [tinyJPEG])
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
                                          messages: [attached], imageData: [tinyJPEG])
        let content = (messages(req)[1])["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(content.first?["text"] as? String, L.t("describe_images"))
    }

    func testRememberedPictureTravelsWithTheNewestQuestion() throws {
        let history = [ChatMessage(role: .user, text: "Male einen Turm im Sturm"),
                       ChatMessage(role: .assistant, text: "Hier ist dein Turm.",
                                   outImages: [Attachment(file: "gen.jpg")]),
                       ChatMessage(role: .user, text: "Warum ist der Himmel dort grau?")]
        let turn = ConversationMemory.turn(from: history) { _ in tinyJPEG }
        XCTAssertTrue(turn.needsVision)
        let req = try QwenAPI.makeRequest(baseURL: baseURL, key: "k", model: "vision",
                                          messages: turn.messages, imageData: turn.images)
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
                                          messages: [ChatMessage(role: .user, text: "x")], imageData: [])
        XCTAssertEqual(req.url?.absoluteString, baseURL + "/chat/completions")
    }

    func testUnparseableBaseURLThrowsLocalisedError() {
        XCTAssertThrowsError(try QwenAPI.makeRequest(baseURL: "http://%zz", key: "k", model: "m",
                                                     messages: [ChatMessage(role: .user, text: "x")],
                                                     imageData: [])) { error in
            XCTAssertEqual((error as? APIError)?.message, L.t("bad_url"))
        }
    }

    func testWhitespaceBaseURLIsPercentEncodedInsteadOfRejected() {
        XCTAssertNoThrow(try QwenAPI.makeRequest(baseURL: "not a url", key: "k", model: "m",
                                                 messages: [ChatMessage(role: .user, text: "x")],
                                                 imageData: []))
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
                                          imageData: [])
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
                                          imageData: [], thinking: .suppressThinking)
        XCTAssertEqual(jsonObject(off)["enable_thinking"] as? Bool, false)
        XCTAssertNil(jsonObject(off)["reasoning_effort"])
    }

    func testChartPlannerRequestCarriesTheSameThinkingDirective() throws {
        let req = try ChartPlanner.makeRequest(baseURL: baseURL, key: "k", model: "qwen3.8-flash",
                                               question: "Einwohner", data: "2024: 84",
                                               thinking: .effort(.off))
        let body = jsonObject(req)
        XCTAssertEqual(body["reasoning_effort"] as? String, "none")
        XCTAssertNil(body["enable_thinking"])
    }

    func testRealtimeURLIsDerivedFromTheHTTPBaseURL() {
        XCTAssertEqual(RealtimeClient.realtimeURL(baseURL: baseURL, model: "qwen-audio")?.absoluteString,
                       "wss://token-plan.example/api-ws/v1/realtime?model=qwen-audio")
        XCTAssertEqual(RealtimeClient.realtimeURL(baseURL: "http://localhost:8080/compatible-mode/v1/", model: "m")?.absoluteString,
                       "ws://localhost:8080/api-ws/v1/realtime?model=m")
    }

    func testWebAnswerRequestUsesTheSharedChatEndpoint() throws {
        let hits = [WebHit(title: "Quelle", url: "https://a.example", domain: "a.example", text: "text")]
        let req = try WebSearch.makeAnswerRequest(baseURL: baseURL, key: "k", model: "m",
                                                 question: "frage", hits: hits)
        XCTAssertEqual(req.url?.absoluteString, baseURL + "/chat/completions")
        XCTAssertEqual(req.timeoutInterval, APITimeout.researchRequest)
        let content = (messages(req).last ?? [:])["content"] as? String ?? ""
        XCTAssertTrue(content.contains("## Quelle [1]"))
        XCTAssertTrue(content.hasSuffix("frage"))
    }
}
