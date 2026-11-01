@testable import GwenMobileFeatureCore
import GwenMobileKit
import MLXLMCommon
import XCTest

final class LocalRequestTests: XCTestCase {
    private let image = "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAFklEQVR42mO4o6FBEmIY1TCqYfhqAAAyBCwQhCQ/2gAAAABJRU5ErkJggg=="

    func testRequestParsesMessagesImagesToolsAndThinking() throws {
        let json = """
        {"model":"mlx-community/gemma-4-e2b-it-4bit","stream":true,"max_tokens":700,
         "reasoning_effort":"none","temperature":0.2,
         "messages":[
           {"role":"system","content":"Du bist Gwen."},
           {"role":"user","content":[{"type":"text","text":"Was ist das?"},
             {"type":"image_url","image_url":{"url":"data:image/png;base64,\(image)"}}]}],
         "tools":[{"type":"function","function":{"name":"answer","description":"Antwortet",
           "parameters":{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}}}]}
        """
        let request = try LocalChatRequest.parse(Data(json.utf8))
        XCTAssertEqual(request.model, "mlx-community/gemma-4-e2b-it-4bit")
        XCTAssertEqual(request.messages.count, 2)
        XCTAssertEqual(request.messages[0].role, .system)
        XCTAssertEqual(request.messages[1].role, .user)
        XCTAssertEqual(request.messages[1].text, "Was ist das?")
        XCTAssertEqual(request.messages[1].images.count, 1)
        XCTAssertFalse(request.messages[1].images[0].isEmpty)
        XCTAssertEqual(request.tools.count, 1)
        XCTAssertEqual(request.maxTokens, 700)
        XCTAssertFalse(request.thinking)
        XCTAssertEqual(request.temperature ?? 0, 0.2)
    }

    func testReasoningEffortLevelAndMissingQuestion() throws {
        let level = """
        {"model":"m","reasoning_effort":"high","messages":[{"role":"user","content":"Hi"}]}
        """
        XCTAssertTrue(try LocalChatRequest.parse(Data(level.utf8)).thinking)
        let noQuestion = """
        {"model":"m","messages":[{"role":"system","content":"Hi"}]}
        """
        XCTAssertThrowsError(try LocalChatRequest.parse(Data(noQuestion.utf8)))
        XCTAssertThrowsError(try LocalChatRequest.parse(Data(#"{"messages":[]}"#.utf8)))
        XCTAssertThrowsError(try LocalChatRequest.parse(Data(#"{"model":"m"}"#.utf8)))
    }

    func testRemoteImagesAndUnknownParts() throws {
        let remote = """
        {"model":"m","messages":[{"role":"user","content":[
          {"type":"text","text":"Bild"},{"type":"image_url","image_url":{"url":"https://x.test/a.png"}}]}]}
        """
        XCTAssertThrowsError(try LocalChatRequest.parse(Data(remote.utf8)))
        let unknown = """
        {"model":"m","messages":[{"role":"user","content":[
          {"type":"audio","text":"ignored"},{"type":"text","text":"Hallo"}]}]}
        """
        XCTAssertEqual(try LocalChatRequest.parse(Data(unknown.utf8)).messages[0].text, "Hallo")
    }

    func testToolRoutingStripsEveryPicture() {
        let tools: [ToolSpec] = [["type": "function"]]
        let request = LocalChatRequest(model: "m", messages: [
            LocalMessage(role: .system, text: "sys"),
            LocalMessage(role: .user, text: "Was ist auf dem Bild?", images: [Data([1, 2, 3])]),
        ], tools: tools, maxTokens: 700, thinking: false, temperature: nil)
        let local = LocalEngine.localRequest(request)
        XCTAssertEqual(local.messages.count, 2)
        XCTAssertTrue(local.messages.allSatisfy(\.images.isEmpty))
    }

    func testPlainQuestionDropsTheRememberedPicture() {
        let request = LocalChatRequest(model: "m", messages: [
            LocalMessage(role: .system, text: "sys"),
            LocalMessage(role: .user, text: "Wann wurde die BRD gegruendet?", images: [Data([1])]),
        ], tools: [], maxTokens: nil, thinking: false, temperature: nil)
        let local = LocalEngine.localRequest(request)
        XCTAssertTrue(local.messages.last?.images.isEmpty ?? false)
    }

    func testPictureQuestionKeepsOnePicture() {
        let request = LocalChatRequest(model: "m", messages: [
            LocalMessage(role: .system, text: "sys"),
            LocalMessage(role: .user, text: "Was ist auf dem Bild?",
                         images: [Data([1]), Data([2])]),
        ], tools: [], maxTokens: nil, thinking: false, temperature: nil)
        let local = LocalEngine.localRequest(request)
        XCTAssertEqual(local.messages.last?.images.count, 1)
    }

    func testLongFileTextDropsTheRememberedPicture() {
        let request = LocalChatRequest(model: "m", messages: [
            LocalMessage(role: .system, text: "sys"),
            LocalMessage(role: .user, text: String(repeating: "image ", count: 1000),
                         images: [Data([1])]),
        ], tools: [], maxTokens: nil, thinking: false, temperature: nil)
        let local = LocalEngine.localRequest(request)
        XCTAssertTrue(local.messages.last?.images.isEmpty ?? false)
    }

    func testLongHistoryIsTrimmedForLocalAnswers() {
        let request = LocalChatRequest(model: "m", messages: [
            LocalMessage(role: .system, text: "sys"),
            LocalMessage(role: .user, text: String(repeating: "a", count: 3000)),
            LocalMessage(role: .assistant, text: "answer"),
            LocalMessage(role: .user, text: "middle"),
            LocalMessage(role: .assistant, text: "latest answer"),
            LocalMessage(role: .user, text: "Wann wurde die BRD gegruendet?"),
        ], tools: [], maxTokens: nil, thinking: false, temperature: nil)
        let local = LocalEngine.localRequest(request)
        XCTAssertEqual(local.messages.count, 4)
        XCTAssertEqual(local.messages.first?.role, .system)
        XCTAssertEqual(local.messages.last?.text, "Wann wurde die BRD gegruendet?")
    }

    func testJSONValuesBecomeSendable() {
        let value: [String: Any] = ["s": "x", "b": true, "i": 4, "d": 1.5,
                                    "a": [1, "z"], "n": ["k": false]]
        let converted = LocalJSON.sendable(value) as? [String: any Sendable]
        XCTAssertEqual(converted?["s"] as? String, "x")
        XCTAssertEqual(converted?["b"] as? Bool, true)
        XCTAssertEqual(converted?["i"] as? Int, 4)
        XCTAssertEqual(converted?["d"] as? Double, 1.5)
        XCTAssertEqual((converted?["a"] as? [any Sendable])?.count, 2)
        XCTAssertNotNil(converted?["n"])
    }
}

final class LocalResponseTests: XCTestCase {
    func testCompletionEncodesToolCallsUsageAndText() throws {
        let result = LocalChatResult(text: "", toolCalls: [
            LocalToolCall(id: "call_1", name: "create_appointment",
                          arguments: #"{"title":"Zahnarzt"}"#),
        ], promptTokens: 12, completionTokens: 3, finishReason: "tool_calls")
        let data = LocalOpenAIResponse.completion(model: "gemma", result: result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let usage = try XCTUnwrap(object["usage"] as? [String: Any])
        XCTAssertEqual(usage["prompt_tokens"] as? Int, 12)
        XCTAssertEqual(usage["completion_tokens"] as? Int, 3)
        XCTAssertEqual(usage["total_tokens"] as? Int, 15)
        let choices = try XCTUnwrap(object["choices"] as? [[String: Any]])
        let message = try XCTUnwrap(choices[0]["message"] as? [String: Any])
        XCTAssertEqual(choices[0]["finish_reason"] as? String, "tool_calls")
        XCTAssertEqual(message["content"] as? String, "")
        let calls = try XCTUnwrap(message["tool_calls"] as? [[String: Any]])
        let function = try XCTUnwrap(calls[0]["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "create_appointment")
        XCTAssertEqual(function["arguments"] as? String, #"{"title":"Zahnarzt"}"#)
    }

    func testChunksDecodeAsChatResponseAndEndWithDone() throws {
        let chunk = LocalOpenAIResponse.chunk(model: "gemma", text: "Hallo")
        XCTAssertTrue(chunk.hasPrefix("data: "))
        let payload = String(chunk.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: Data(payload.utf8))
        XCTAssertEqual(decoded.streamChunk, "Hallo")
        let tool = LocalOpenAIResponse.toolChunk(model: "gemma",
                                                 call: LocalToolCall(id: "c", name: "answer", arguments: "{}"),
                                                 index: 0)
        XCTAssertTrue(tool.contains("\"tool_calls\""))
        let final = LocalOpenAIResponse.finalChunk(model: "gemma", reason: "stop")
        XCTAssertTrue(final.contains("\"finish_reason\":\"stop\""))
        XCTAssertEqual(LocalOpenAIResponse.done(), "data: [DONE]\n\n")
    }

    func testModelsAndErrorsAreJSON() throws {
        let models = try XCTUnwrap(JSONSerialization.jsonObject(with: LocalOpenAIResponse.models(["b", "a"]))
            as? [String: Any])
        let entries = try XCTUnwrap(models["data"] as? [[String: Any]])
        XCTAssertEqual(entries.compactMap { $0["id"] as? String }, ["a", "b"])
        let error = try XCTUnwrap(JSONSerialization.jsonObject(with: LocalOpenAIResponse.error("kaputt"))
            as? [String: Any])
        let nested = try XCTUnwrap(error["error"] as? [String: Any])
        XCTAssertEqual(nested["message"] as? String, "kaputt")
    }

    func testStatusMapping() {
        XCTAssertEqual(LocalOpenAI.status(for: APIError(message: "x", status: 429)), 429)
        XCTAssertEqual(LocalOpenAI.status(for: LocalRequestError.empty), 400)
        XCTAssertEqual(LocalOpenAI.status(for: LocalEngineError.notInstalled("m")), 503)
        XCTAssertEqual(LocalOpenAI.status(for: CancellationError()), 500)
    }
}

final class HuggingFaceMLXCatalogTests: XCTestCase {
    private func decodedSummary(_ id: String, tags: [String], pipeline: String) throws
        -> HuggingFaceMLXCatalog.Summary {
        let object: [String: Any] = ["id": id, "library_name": "mlx", "tags": tags, "pipeline_tag": pipeline]
        return try JSONDecoder().decode(HuggingFaceMLXCatalog.Summary.self,
                                        from: JSONSerialization.data(withJSONObject: object))
    }

    func testParameterBillionsComesFromTheModelName() {
        XCTAssertEqual(HuggingFaceMLXCatalog.parameterBillions(
            from: "mlx-community/gemma-4-e2b-it-4bit"), 2)
        XCTAssertEqual(HuggingFaceMLXCatalog.parameterBillions(
            from: "mlx-community/gemma-4-e4b-it-4bit"), 4)
        XCTAssertEqual(HuggingFaceMLXCatalog.parameterBillions(
            from: "mlx-community/Qwen3.5-9B-MLX-4bit"), 9)
        XCTAssertEqual(HuggingFaceMLXCatalog.parameterBillions(
            from: "mlx-community/Qwen3.8-27B-4bit"), 27)
    }

    func testTheSearchFilterKeepsOnlyMlxChatModels() throws {
        let good = try decodedSummary("mlx-community/Qwen3.5-9B-MLX-4bit", tags: ["mlx", "safetensors", "4-bit"], pipeline: "image-text-to-text")
        let embedding = try decodedSummary("mlx-community/Qwen3-Embedding-4B-4bit-DWQ", tags: ["mlx", "safetensors", "4-bit"], pipeline: "feature-extraction")
        let tooLarge = try decodedSummary("mlx-community/Qwen3.8-27B-4bit", tags: ["mlx", "safetensors", "4-bit"], pipeline: "image-text-to-text")
        XCTAssertTrue(HuggingFaceMLXCatalog.passesBaseFilter(good))
        XCTAssertFalse(HuggingFaceMLXCatalog.passesBaseFilter(embedding))
        XCTAssertTrue(HuggingFaceMLXCatalog.passesBaseFilter(tooLarge))
    }

    func testAVisionModelBuildsAChoiceWithSizeAndRam() async throws {
        let summary = try decodedSummary("mlx-community/gemma-4-e2b-it-4bit", tags: ["mlx", "safetensors", "4-bit", "image-text-to-text"], pipeline: "image-text-to-text")
        let detail = try JSONDecoder().decode(HuggingFaceMLXCatalog.Detail.self, from: Data("""
        {"id":"mlx-community/gemma-4-e2b-it-4bit","library_name":"mlx",
         "tags":["mlx","safetensors","4-bit","image-text-to-text"],
         "pipeline_tag":"image-text-to-text",
         "config":{"model_type":"gemma4","max_position_embeddings":131072},
         "siblings":[{"rfilename":"config.json","size":100},
                     {"rfilename":"tokenizer.json","size":100},
                     {"rfilename":"model.safetensors","size":3580000000}]}
        """.utf8))
        let choice = await HuggingFaceMLXCatalog().choice(summary: summary, detail: detail)
        XCTAssertEqual(choice?.id, "mlx-community/gemma-4-e2b-it-4bit")
        XCTAssertEqual(choice?.family, .gemma)
        XCTAssertEqual(choice?.vision, true)
        XCTAssertEqual(choice?.parameterBillions, 2)
        XCTAssertEqual(choice?.quantization, "4-bit")
        XCTAssertEqual(choice?.context, "128K")
        XCTAssertEqual(choice?.source, .huggingFace)
        XCTAssertEqual(choice?.bytes, 3_580_000_200)
    }

    func testATextModelBuildsANonVisionChoice() async throws {
        let summary = try decodedSummary("mlx-community/Llama-3.1-8B-Instruct-4bit", tags: ["mlx", "safetensors", "4-bit"], pipeline: "text-generation")
        let detail = try JSONDecoder().decode(HuggingFaceMLXCatalog.Detail.self, from: Data("""
        {"id":"mlx-community/Llama-3.1-8B-Instruct-4bit","library_name":"mlx",
         "tags":["mlx","safetensors","4-bit"],"pipeline_tag":"text-generation",
         "config":{"model_type":"llama","max_position_embeddings":131072},
         "siblings":[{"rfilename":"config.json","size":100},
                     {"rfilename":"tokenizer.json","size":100},
                     {"rfilename":"model.safetensors","size":5000000000}]}
        """.utf8))
        let choice = await HuggingFaceMLXCatalog().choice(summary: summary, detail: detail)
        XCTAssertEqual(choice?.vision, false)
        XCTAssertEqual(choice?.family, .other)
        XCTAssertEqual(choice?.parameterBillions, 8)
    }

    func testAnUnknownArchitectureIsNotOffered() async throws {
        let summary = try decodedSummary("mlx-community/Unknown-7B-4bit", tags: ["mlx", "safetensors", "4-bit"], pipeline: "text-generation")
        let detail = try JSONDecoder().decode(HuggingFaceMLXCatalog.Detail.self, from: Data("""
        {"id":"mlx-community/Unknown-7B-4bit","library_name":"mlx",
         "tags":["mlx","safetensors","4-bit"],"pipeline_tag":"text-generation",
         "config":{"model_type":"unknown_architecture"},
         "siblings":[{"rfilename":"config.json","size":100},
                     {"rfilename":"tokenizer.json","size":100},
                     {"rfilename":"model.safetensors","size":5000000000}]}
        """.utf8))
        let choice = await HuggingFaceMLXCatalog().choice(summary: summary, detail: detail)
        XCTAssertNil(choice)
    }
}

final class LocalModelConfigurationsTests: XCTestCase {
    func testQwenUsesItsOwnReasoningAndTokenizer() {
        let qwen = LocalModelConfigurations.configuration(for: LocalModelConfigurations.qwen9BID)
        XCTAssertEqual(qwen.extraEOSTokens, ["<|im_end|>"])
        XCTAssertNil(qwen.reasoningConfig)
        let gemma = LocalModelConfigurations.configuration(for: LocalModelConfigurations.gemmaE2BID)
        XCTAssertEqual(gemma.extraEOSTokens, ["<turn|>"])
        XCTAssertNotNil(gemma.reasoningConfig)
    }
}

final class LocalCatalogTests: XCTestCase {
    func testCatalogAndEndpoint() {
        XCTAssertEqual(LocalEndpoint.baseURL, "http://gwen.local/v1")
        XCTAssertEqual(LocalEndpoint.host, "gwen.local")
        let request = URLRequest(url: URL(string: LocalEndpoint.baseURL + "/models")!)
        XCTAssertTrue(LocalEndpoint.isLocal(request))
        XCTAssertFalse(LocalEndpoint.isLocal(URLRequest(url: URL(string: "https://x.test")!)))
        XCTAssertNil(LocalCatalog.choice(for: "x"))
    }

    func testRegisteredHuggingFaceChoiceIsVisible() {
        let choice = LocalModelChoice(id: "mlx-community/Test-8B-4bit", name: "Test 8B",
                                      family: .other, bytes: 5_000_000_000, minRamGB: 12,
                                      context: "32K", vision: false, tools: true,
                                      source: .huggingFace, parameterBillions: 8,
                                      quantization: "4-bit")
        LocalCatalog.register([choice])
        XCTAssertEqual(LocalCatalog.choice(for: choice.id), choice)
    }

    func testCapabilitiesForInstalledModelsOnly() async {
        let choice = LocalModelChoice(id: "mlx-community/Test-Vision-4bit", name: "Test Vision",
                                      family: .other, bytes: 3_000_000_000, minRamGB: 8,
                                      context: "32K", vision: true, tools: true,
                                      source: .huggingFace)
        LocalCatalog.register([choice])
        let discoverer = LocalCapabilityDiscoverer()
        let found = await discoverer.discover(baseURL: LocalEndpoint.baseURL, key: "",
                                              models: [choice.id, "unknown"])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[choice.id]?.vision, .supported)
        XCTAssertTrue(found[choice.id]?.thinking.canSwitchOff ?? false)
        XCTAssertEqual(found[choice.id]?.thinking.encoding, .openAI)
    }

    func testDescriptorUsesTheLocalEndpoint() {
        let descriptor = LocalProviderDescriptor()
        XCTAssertEqual(descriptor.baseURL(ProviderConnections()), LocalEndpoint.baseURL)
        XCTAssertEqual(descriptor.capabilities.vision, .probed)
        XCTAssertEqual(descriptor.capabilities.image, .unavailable)
        XCTAssertTrue(descriptor.isConfigured(ProviderConnections(), key: ""))
        XCTAssertEqual(descriptor.keychainAccount, "local_device_no_key")
        XCTAssertFalse(descriptor.title.isEmpty)
        XCTAssertFalse(descriptor.footer.isEmpty)
        XCTAssertFalse(descriptor.modelsFooter.isEmpty)
    }

    func testMemoryReportsBounds() {
        XCTAssertGreaterThan(LocalMemory.physical, 0)
        XCTAssertGreaterThanOrEqual(LocalMemory.available, 0)
        XCTAssertFalse(LocalMemory.label.isEmpty)
        XCTAssertTrue(LocalMemory.canFit(1))
        XCTAssertFalse(LocalMemory.canFit(LocalMemory.physical * 2))
        XCTAssertGreaterThan(LocalMemory.generationFloor, 0)
        XCTAssertGreaterThan(LocalMemory.mlxLimit, Int(LocalMemory.physical / 2))
        XCTAssertTrue(LocalMemory.canHost(1))
    }

    func testMinimumMemoryMatchesTheHostGate() {
        XCTAssertEqual(LocalMemory.minRamGB(for: 0), 8)
        XCTAssertEqual(LocalMemory.minRamGB(for: 3_583_086_498), 8)
        XCTAssertEqual(LocalMemory.minRamGB(for: 4_622_110_691), 9)
        XCTAssertEqual(LocalMemory.minRamGB(for: 5_977_071_067), 10)
        let required = Int64(LocalMemory.minRamGB(for: 5_977_071_067)) * 1_000_000_000
        XCTAssertGreaterThanOrEqual(required, 5_977_071_067 + LocalMemory.hostReserve)
    }
}

final class LocalFilesTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testManifestRequiresMarkerConfigTokenizerAndWeights() throws {
        let files = LocalModelFiles(root: root)
        let id = "mlx-community/Test-Manifest-4bit"
        XCTAssertFalse(files.isInstalled(id))
        let folder = files.directory(for: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("tokenizer.json"))
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("model.safetensors"))
        let manifest = LocalModelManifest(repo: id, bytes: 3)
        try files.write(manifest, for: id)
        XCTAssertTrue(files.isInstalled(id))
        XCTAssertEqual(files.installedIDs(), [id])
        XCTAssertEqual(files.manifest(for: id), manifest)
        try files.remove(id)
        XCTAssertFalse(files.isInstalled(id))
        XCTAssertTrue(files.installedIDs().isEmpty)
    }

    func testADynamicManifestSurvivesTheBuiltInCatalog() throws {
        let files = LocalModelFiles(root: root)
        let id = "mlx-community/Test-8B-4bit"
        let folder = files.directory(for: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("tokenizer.json"))
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("model.safetensors"))
        let manifest = LocalModelManifest(repo: id, bytes: 3,
                                          name: "Test 8B", family: .other, context: "32K",
                                          vision: false, tools: true, parameterBillions: 8,
                                          quantization: "4-bit", source: .huggingFace)
        try files.write(manifest, for: id)
        let choices = files.installedChoices()
        XCTAssertEqual(choices.map(\.id), [id])
        XCTAssertEqual(choices.first?.source, .huggingFace)
        XCTAssertEqual(choices.first?.vision, false)
        XCTAssertEqual(choices.first?.parameterBillions, 8)
    }

    func testFolderNamesAreFlat() {
        XCTAssertEqual(LocalModelFiles.folderName("mlx-community/gemma-4-e2b-it-4bit"),
                       "mlx-community--gemma-4-e2b-it-4bit")
    }
}

@MainActor
final class LocalStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testStoreShowsInstalledAndDeletesIt() throws {
        let files = LocalModelFiles(root: root)
        let id = "mlx-community/Test-Store-4bit"
        let folder = files.directory(for: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("tokenizer.json"))
        try Data([1]).write(to: folder.appendingPathComponent("model.safetensors"))
        let manifest = LocalModelManifest(repo: id, bytes: 1)
        try files.write(manifest, for: id)
        let store = LocalModelStore(files: files)
        let choice = LocalCatalog.fallback(manifest: manifest, id: id)
        XCTAssertEqual(store.status(for: choice).phase, .installed)
        XCTAssertTrue(store.isInstalled(choice))
        XCTAssertEqual(store.installedChoices().map(\.id), [id])
        store.delete(choice)
        XCTAssertEqual(store.status(for: choice).phase, .absent)
        XCTAssertFalse(store.isInstalled(choice))
    }

    func testStoreStartsWithNoModels() {
        let store = LocalModelStore(files: LocalModelFiles(root: root))
        XCTAssertTrue(store.choices.isEmpty)
    }

    func testAFailedRemovalKeepsTheModelInstalled() throws {
        let files = LocalModelFiles(root: root)
        let id = "mlx-community/Test-Locked-4bit"
        let folder = files.directory(for: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("tokenizer.json"))
        try Data([1]).write(to: folder.appendingPathComponent("model.safetensors"))
        let manifest = LocalModelManifest(repo: id, bytes: 1)
        try files.write(manifest, for: id)
        let store = LocalModelStore(files: files)
        let choice = LocalCatalog.fallback(manifest: manifest, id: id)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: folder.path) }
        XCTAssertFalse(store.delete(choice))
        XCTAssertTrue(files.isInstalled(id))
        XCTAssertEqual(store.status(for: choice).phase, .installed)
    }
}

final class LocalThinkingFilterTests: XCTestCase {
    func testThinkingIsRemovedInOnePiece() {
        var filter = LocalThinkingFilter()
        XCTAssertEqual(filter.feed("<|channel>thought\nGeheim<channel|>Hallo"), "Hallo")
        XCTAssertEqual(filter.finish(), "")
    }

    func testThinkingIsRemovedAcrossChunks() {
        var filter = LocalThinkingFilter()
        XCTAssertEqual(filter.feed("<|chan"), "")
        XCTAssertEqual(filter.feed("nel>thought Geheim<chan"), "")
        XCTAssertEqual(filter.feed("nel|>Welt"), "Welt")
        XCTAssertEqual(filter.finish(), "")
    }

    func testPlainTextFlowsImmediately() {
        var filter = LocalThinkingFilter()
        XCTAssertEqual(filter.feed("Hallo Welt"), "Hallo Welt")
        XCTAssertEqual(filter.finish(), "")
    }

    func testAPartialMarkerAtTheEndIsKept() {
        var filter = LocalThinkingFilter()
        XCTAssertEqual(filter.feed("Hallo<|ch"), "Hallo")
        XCTAssertEqual(filter.finish(), "<|ch")
    }

    func testUnfinishedThinkingIsDropped() {
        var filter = LocalThinkingFilter()
        XCTAssertEqual(filter.feed("<|channel>thought Geheim"), "")
        XCTAssertEqual(filter.finish(), "")
    }

    func testQwenThinkingIsRemoved() {
        var filter = LocalThinkingFilter(start: "<think>", end: "</think>")
        XCTAssertEqual(filter.feed("<think>Geheim</think>Hallo"), "Hallo")
        XCTAssertEqual(filter.finish(), "")
    }

    func testQwenPrefilledThinkingIsRemoved() {
        var filter = LocalThinkingFilter(start: "<think>", end: "</think>", primed: true)
        XCTAssertEqual(filter.feed("Geheim</think>391"), "391")
        XCTAssertEqual(filter.finish(), "")
    }

    func testPlainTextLongerThanTheMarkerFlows() {
        var filter = LocalThinkingFilter()
        let text = "Das ist eine ganz normale Antwort ohne Denken."
        XCTAssertEqual(filter.feed(text), text)
        XCTAssertEqual(filter.finish(), "")
    }
}

extension LocalCatalogTests {
    func testTheLocalListerAndPresetFlag() async throws {
        let list = try await LocalModelLister().list(baseURL: LocalEndpoint.baseURL, key: "")
        XCTAssertTrue(list.imageModels.isEmpty)
        XCTAssertTrue(LocalProviderDescriptor().usesPresetURL(ProviderConnections()))
    }
}

final class LocalDownloadErrorTests: GwenTestCase {
    func testTheDownloadErrorsSpeakTheAppLanguage() {
        XCTAssertEqual(LocalDownloadError.emptyPlan.errorDescription, "No files were found in the model.")
        XCTAssertEqual(LocalDownloadError.noWeights.errorDescription, "The model contains no weights.")
        XCTAssertEqual(LocalDownloadError.http(404).errorDescription, "HTTP 404")
        let space = LocalDownloadError.noSpace(needed: 3_000_000_000, available: 1_000_000_000)
        XCTAssertEqual(space.errorDescription,
                       L.fmt2("local_download_no_space", StorageUsage.bytesText(3_000_000_000),
                              StorageUsage.bytesText(1_000_000_000)))
        L.apply(.de)
        XCTAssertEqual(LocalDownloadError.noWeights.errorDescription, "Das Modell enthält keine Gewichte.")
        L.apply(.en)
    }
}

final class HuggingFaceHubTests: XCTestCase {
    func testOnlyModelFilesAreDownloaded() {
        for path in ["model.safetensors", "config.json", "chat_template.jinja", "sub/tokenizer.json"] {
            XCTAssertTrue(HuggingFaceHub.isModelFile(path), path)
        }
        for path in ["", "folder/", ".gitattributes", "README.md", "readme.json", "weights.bin"] {
            XCTAssertFalse(HuggingFaceHub.isModelFile(path), path)
        }
    }

    func testRepoAndFilePathsAreEscapedPerSegment() {
        XCTAssertEqual(HuggingFaceHub.detailURL(for: "mlx-community/Qwen 3")?.absoluteString,
                       "https://huggingface.co/api/models/mlx-community/Qwen%203?blobs=true")
        XCTAssertEqual(HuggingFaceHub.fileURL(repo: "mlx-community/Qwen 3", path: "sub dir/model.safetensors")?
            .absoluteString,
                       "https://huggingface.co/mlx-community/Qwen%203/resolve/main/sub%20dir/model.safetensors")
    }
}
