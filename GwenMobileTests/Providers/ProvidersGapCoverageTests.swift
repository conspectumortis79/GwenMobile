@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import Security
import XCTest
import GwenMobileKit

final class ProviderDecodingGapTests: XCTestCase {
    func testDescriptorDefaultsAndModelDiscoverers() {
        XCTAssertEqual(ProviderID.qwenCloud.id, "qwen")
        XCTAssertEqual(ProviderID.openAICompatible.id, "openai")
        let openAI = OpenAICompatibleDescriptor()
        XCTAssertEqual(openAI.consoleLinkTitle, "")
        XCTAssertNil(openAI.imageBackend)
        XCTAssertEqual(openAI.keyPlaceholder(ProviderConnections()), "sk-…")
        XCTAssertTrue(openAI.usesPresetURL(ProviderConnections()))
        for descriptor in ProviderCatalog.all {
            XCTAssertNotNil(descriptor.modelDiscoverer)
            XCTAssertNotNil(descriptor.modelLister)
        }
    }

    func testLooseProfilesFallBackToEveryDefault() throws {
        let profile = try JSONDecoder().decode(ProviderProfile.self, from: Data("{}".utf8))
        XCTAssertEqual(profile, ProviderProfile())
        let caps = try JSONDecoder().decode(ThinkingCapabilities.self, from: Data("{}".utf8))
        XCTAssertEqual(caps, ThinkingCapabilities())
    }

    func testDeepSeekEffortAndModalityDefaults() throws {
        let effort = try JSONDecoder().decode(DeepSeekModelEntry.Effort.self,
                                             from: Data(#"{"default_level":"high"}"#.utf8))
        XCTAssertEqual(effort.supportedLevels, [])
        let flat = try JSONDecoder().decode(DeepSeekModelEntry.self,
                                           from: Data(#"{"id":"flat","default_level":"high"}"#.utf8))
        XCTAssertEqual(flat.effort?.supportedLevels, [])
        XCTAssertNotNil(flat.effort)
        let bare = try JSONDecoder().decode(DeepSeekModelEntry.self, from: Data(#"{"id":"bare"}"#.utf8))
        XCTAssertNil(bare.inputModalities)
        XCTAssertEqual(DeepSeekModelCatalog.vision(of: bare), .unknown)
    }

    func testOpenRouterReasoningWithoutMandatory() throws {
        let entry = try JSONDecoder().decode(OpenRouterModelEntry.self,
                                             from: Data(#"{"id":"x","reasoning":{}}"#.utf8))
        XCTAssertEqual(entry.reasoning?.mandatory, false)
        XCTAssertEqual(entry.reasoning?.effortsListed, false)
        XCTAssertNil(entry.reasoning?.supportedEfforts)
    }

    func testEveryThinkingLabelAndDirective() {
        for level in ThinkingLevel.allCases {
            XCTAssertFalse(level.labelKey.isEmpty, "\(level)")
        }
        var body: [String: Any] = ["model": "m"]
        ThinkingDirective.effort(.low, .openAI).applied(to: &body)
        XCTAssertEqual(body["reasoning_effort"] as? String, "low")
        XCTAssertEqual(body["model"] as? String, "m")
    }

    func testBooleanAndDataErrorShapes() {
        XCTAssertEqual(APIErrorParser.message(from: #"{"error":{"message":true}}"#, status: 500), "true")
        XCTAssertEqual(APIErrorParser.message(from: #"{"error":{"message":false}}"#, status: 500), "false")
        XCTAssertEqual(APIErrorParser.message(from: Data(#"{"error":{"message":"kaputt"}}"#.utf8),
                                              status: 500), "kaputt")
        XCTAssertEqual(APIErrorParser.message(from: Data([0xFF, 0xFE]), status: 400), "HTTP 400")
    }
}

@MainActor
final class ProviderNetworkGapTests: GwenTestCase {
    override func tearDown() {
        MockHTTP.uninstall()
        super.tearDown()
    }

    func testTheListersReadModelsAndFallBackWithoutImageModels() async throws {
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/videos/models") {
                return (200, Data(#"{"data":[{"id":"video-model"}]}"#.utf8))
            }
            if url.contains("/images/models") { return (200, Data(#"{"data":[{"id":"wan"}]}"#.utf8)) }
            if url.contains("/models") { return (200, Data(#"{"data":[{"id":"m2"},{"id":"m1"}]}"#.utf8)) }
            return (200, Data("{}".utf8))
        }
        let openAI = try await OpenAIModelLister().list(baseURL: "https://q.test/v1", key: "k")
        XCTAssertEqual(openAI.models, ["m1", "m2"])
        let qwenModels = try await QwenAPI.fetchModels(baseURL: "https://q.test/v1", key: "k")
        XCTAssertEqual(qwenModels, ["m1", "m2"])
        let router = try await OpenRouterModelLister().list(baseURL: "https://q.test/v1", key: "k")
        XCTAssertEqual(router.models, ["m1", "m2"])
        XCTAssertEqual(router.imageModels, ["wan"])
        XCTAssertEqual(router.videoGenerationModels, ["video-model"])
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("/videos/models") { return (500, Data("{}".utf8)) }
            if url.contains("/images/models") { return (500, Data("{}".utf8)) }
            return (200, Data(#"{"data":[{"id":"m1"}]}"#.utf8))
        }
        let fallback = try await OpenRouterModelLister().list(baseURL: "https://q.test/v1", key: "k")
        XCTAssertEqual(fallback.imageModels, ModelFilter.imageCandidates(["m1"]))
    }

    func testTheDiscoveredCapabilitiesComeFromTheModelList() async {
        MockHTTP.install { _ in (200, Data(#"{"data":[{"id":"m1"},{"id":"m2"}]}"#.utf8)) }
        let found = await DeepSeekModelCatalog().discover(baseURL: "https://q.test/v1", key: "k",
                                                          models: ["m1", "nicht/da"])
        XCTAssertEqual(found.keys.sorted(), ["m1"])
    }

    func testTheOpenAIProberMergesThinkingAndVision() async {
        MockHTTP.install { _ in
            let message = "'reasoning_effort' must be one of: 'low', 'high'"
            return (400, Data(#"{"error":{"message":"\#(message)"}}"#.utf8))
        }
        let caps = await CapabilityProber.openAI.discover(baseURL: "https://q.test/v1", key: "k",
                                                          models: ["m1", "m2", "m3", "m4", "m5"])
        XCTAssertEqual(caps.keys.sorted(), ["m1", "m2", "m3", "m4", "m5"])
        XCTAssertEqual(caps["m1"]?.thinking.levels, [.low, .high])
        XCTAssertEqual(caps["m1"]?.vision, .rejected)
    }

    func testTheDashScopeProberRunsTheSameTwoProbes() async {
        MockHTTP.install { _ in
            let message = "'reasoning_effort' must be one of: 'low'"
            return (400, Data(#"{"error":{"message":"\#(message)"}}"#.utf8))
        }
        let caps = await CapabilityProber.dashScope.discover(baseURL: "https://q.test/v1", key: "k",
                                                             models: ["m1"])
        XCTAssertEqual(caps["m1"]?.thinking.levels, [.low])
        XCTAssertEqual(caps["m1"]?.thinking.canSwitchOff, false)
        XCTAssertEqual(caps["m1"]?.vision, .rejected)
    }

    func testDeepSeekAndRouterBalances() async {
        MockHTTP.install { _ in
            (200, Data(#"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"12.50"}]}"#.utf8))
        }
        let balance = try? await DeepSeekAPI.fetchBalance(key: "k")
        XCTAssertEqual(balance?.balanceInfos.first?.totalBalance, "12.50")
        let deepSeekText = await DeepSeekDescriptor().accountBalance(key: "k")
        XCTAssertNotNil(deepSeekText)
        MockHTTP.install { _ in (200, Data(#"{"data":{"limit_remaining":2.5,"usage":1.25}}"#.utf8)) }
        let info = try? await OpenRouterAPI.fetchKeyInfo(key: "k")
        XCTAssertEqual(info?.data.limitRemaining, 2.5)
        let routerText = await OpenRouterDescriptor().accountBalance(key: "k")
        XCTAssertEqual(routerText, L.fmt("openrouter_remaining", OpenRouterAPI.dollars(2.5)))
    }

    func testTheImagePromptAndImageParsing() async throws {
        MockHTTP.install { _ in
            (200, ToolCallPayload.call(ToolRouter.composeImagePromptTool,
                                       ["status": "resolved",
                                        "prompt": "Ein sehr detaillierter Prompt"]))
        }
        let prompt = try await QwenAPI.composeImagePrompt(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                          instruction: "mal etwas", history: [],
                                                          thinking: .nothing)
        XCTAssertEqual(prompt, "Ein sehr detaillierter Prompt")
        MockHTTP.install { _ in
            (200, ToolCallPayload.call(ToolRouter.composeImagePromptTool,
                                       ["status": "unresolved", "prompt": ""]))
        }
        let unresolved = try await QwenAPI.composeImagePrompt(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                              instruction: "mal etwas", history: [],
                                                              thinking: .nothing)
        XCTAssertNil(unresolved)
        let noteRequest = try QwenAPI.makeImageRequest(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                       prompt: "mal etwas", inputImages: [])
        MockHTTP.install { _ in
            (200, Data(#"{"choices":[{"message":{"content":[{"text":"kein bild"}]}}]}"#.utf8))
        }
        do {
            _ = try await QwenAPI.generateImage(req: noteRequest)
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("kein bild"), error.localizedDescription)
        }
        MockHTTP.install { _ in
            (200, Data(#"{"choices":[{"message":{"content":[{"image":"https://x.test/a.png"}]}}]}"#.utf8))
        }
        let urls = try await QwenAPI.generateImage(req: noteRequest)
        XCTAssertEqual(urls.first?.absoluteString, "https://x.test/a.png")
    }

    func testTheOpenRouterBackendStoresInlinePictures() async throws {
        let bytes = Data([9, 8, 7])
        MockHTTP.install { _ in
            (200, Data(#"{"data":[{"b64_json":"\#(bytes.base64EncodedString())"}]}"#.utf8))
        }
        let pictures = try await OpenRouterImageBackend().generate(baseURL: "https://q.test/v1", key: "k",
                                                                   model: "m", prompt: "p",
                                                                   inputImages: [], isEdit: false)
        XCTAssertEqual(pictures, [.inline(bytes)])
    }

    func testTheAuxiliaryProbesWithoutAUsableBaseURL() async throws {
        let support = await VisionCapabilityProbe.support(baseURL: "", key: "k", model: "m")
        XCTAssertEqual(support, .unknown)
        let answer = try await QwenAPI.resolveQuery(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                    history: [ChatMessage(role: .user, text: "   ")],
                                                    thinking: .nothing)
        XCTAssertNil(answer)
    }

    func testTheResolverRewritesTheGivenWishInsteadOfTheWholeMessage() async throws {
        let sent = LockedValue("")
        MockHTTP.install { request in
            sent.set(MockHTTP.body(of: request))
            return (200, ToolCallPayload.call(ToolRouter.resolveQueryTool,
                                              ["status": "resolved", "query": "Jura ENA 4 Kaffeevollautomat"]))
        }
        let message = ChatMessage(role: .user, text: "Was ist das für ein Gerät? Such mir das günstigste Angebot.")
        let query = try await QwenAPI.resolveQuery(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                   history: [message], question: "Was ist das für ein Gerät?",
                                                   thinking: .nothing)
        XCTAssertEqual(query, "Jura ENA 4 Kaffeevollautomat")
        XCTAssertTrue(sent.current.contains("Was ist das für ein Gerät?"), sent.current)
        XCTAssertFalse(sent.current.contains("günstigste Angebot"), sent.current)
    }

    func testTheRateLimitRetryWaitsAndReturnsTheLateAnswer() async throws {
        let calls = LockedValue(0)
        let value = try await RateLimitRetry.run(attempts: 3, backoff: .milliseconds(1)) {
            let attempt = calls.mutate { box -> Int in
                box += 1
                return box
            }
            guard attempt > 2 else { throw APIError(message: "rate limit", status: 429) }
            return 7
        }
        XCTAssertEqual(value, 7)
        XCTAssertEqual(calls.current, 3)
    }
}

@MainActor
final class ProviderVaultGapTests: XCTestCase {
    private var accounts: [ProviderID: String] {
        [.qwenCloud: "qwen_key", .openAICompatible: "openai_key", .openRouter: "router_key"]
    }

    func testValuesForUnknownProvidersAndAnEmptyBlockedSet() {
        let store = GapRecordingStore(stored: [:])
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        XCTAssertEqual(vault.value(for: .deepSeek), "")
        XCTAssertEqual(vault.reloadBlocked(), [])
        XCTAssertEqual(vault.persist(.deepSeek), .untouched)
        vault.seed("sk-x", for: .deepSeek)
        XCTAssertEqual(store.savedAccounts, [])
        vault.requestClear(.deepSeek)
        XCTAssertEqual(vault.persist(.deepSeek), .untouched)
    }

    func testABlockedAbsentEntryRecoversWithoutAValue() {
        let store = GapRecordingStore(stored: ["openai_key": "sk-or"])
        store.blocked = ["openai_key"]
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        XCTAssertTrue(vault.hasBlockedEntry)
        store.values["openai_key"] = nil
        store.blocked = []
        XCTAssertEqual(vault.reloadBlocked(), [.openAICompatible])
        XCTAssertEqual(vault.value(for: .openAICompatible), "")
        XCTAssertFalse(vault.hasBlockedEntry)
    }

    func testAFailingKeychainReportsTheClearAsFailed() {
        let store = GapRecordingStore(stored: ["qwen_key": "sk-echt"])
        store.refusesDelete = true
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        vault.requestClear(.qwenCloud)
        XCTAssertEqual(vault.persist(.qwenCloud), .failed)
        XCTAssertEqual(store.read(account: "qwen_key"), .value("sk-echt"))
    }
}

private final class GapRecordingStore: KeyStoring, @unchecked Sendable {
    var values: [String: String]
    var blocked: Set<String> = []
    var refusesDelete = false
    private(set) var savedAccounts: [String] = []

    init(stored: [String: String]) {
        values = stored
    }

    func read(account: String) -> KeychainRead {
        if blocked.contains(account) { return .blocked(status: -25308) }
        guard let value = values[account], !value.isEmpty else { return .absent }
        return .value(value)
    }

    @discardableResult
    func save(_ value: String, account: String) -> Bool {
        guard !value.isEmpty else { return false }
        savedAccounts.append(account)
        values[account] = value
        blocked.remove(account)
        return true
    }

    @discardableResult
    func delete(account: String) -> Bool {
        guard !refusesDelete else { return false }
        values[account] = nil
        blocked.remove(account)
        return true
    }
}

final class KeychainKeyStoreGapTests: XCTestCase {
    func testTheKeychainFailureStatusesAreReported() {
        let copy = KeychainInterop.copyMatching
        let update = KeychainInterop.updateItem
        let add = KeychainInterop.addItem
        let remove = KeychainInterop.deleteItem
        defer {
            KeychainInterop.copyMatching = copy
            KeychainInterop.updateItem = update
            KeychainInterop.addItem = add
            KeychainInterop.deleteItem = remove
        }
        KeychainInterop.copyMatching = { _ in (errSecNotAvailable, nil) }
        let store = KeychainKeyStore(service: "GwenMobileTests")
        XCTAssertTrue(store.read(account: "a").isBlocked)
        KeychainInterop.updateItem = { _, _ in errSecIO }
        XCTAssertFalse(store.save("x", account: "a"))
        KeychainInterop.updateItem = { _, _ in errSecItemNotFound }
        KeychainInterop.addItem = { _ in errSecIO }
        XCTAssertFalse(store.save("x", account: "a"))
        KeychainInterop.deleteItem = { _ in errSecIO }
        XCTAssertFalse(store.delete(account: "a"))
    }

    func testTheKeychainSuccessPathsAndAccessibilityUpgrade() {
        let copy = KeychainInterop.copyMatching
        let update = KeychainInterop.updateItem
        let add = KeychainInterop.addItem
        let remove = KeychainInterop.deleteItem
        defer {
            KeychainInterop.copyMatching = copy
            KeychainInterop.updateItem = update
            KeychainInterop.addItem = add
            KeychainInterop.deleteItem = remove
        }
        let store = KeychainKeyStore(service: "GwenMobileTests")
        KeychainInterop.copyMatching = { _ in
            (errSecSuccess, [kSecValueData as String: Data("secret".utf8),
                             kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock] as NSDictionary)
        }
        XCTAssertEqual(store.read(account: "a"), .value("secret"))
        KeychainInterop.copyMatching = { _ in
            (errSecSuccess, [kSecValueData as String: Data("old".utf8),
                             kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked] as NSDictionary)
        }
        let updates = LockedValue(0)
        KeychainInterop.updateItem = { _, _ in
            updates.mutate { $0 += 1 }
            return errSecSuccess
        }
        XCTAssertEqual(store.read(account: "a"), .value("old"))
        XCTAssertEqual(updates.current, 1)
        KeychainInterop.copyMatching = { _ in (errSecSuccess, [:] as NSDictionary) }
        XCTAssertEqual(store.read(account: "a"), .absent)
        KeychainInterop.copyMatching = { _ in (errSecItemNotFound, nil) }
        XCTAssertEqual(store.read(account: "a"), .absent)
        KeychainInterop.updateItem = { _, _ in errSecSuccess }
        XCTAssertTrue(store.save("x", account: "a"))
        KeychainInterop.updateItem = { _, _ in errSecItemNotFound }
        KeychainInterop.addItem = { _ in errSecSuccess }
        XCTAssertTrue(store.save("x", account: "a"))
        KeychainInterop.deleteItem = { _ in errSecSuccess }
        XCTAssertTrue(store.delete(account: "a"))
        _ = add([kSecClass as String: kSecClassGenericPassword])
    }

    func testAReadWithoutKeychainAccessIsReportedWithoutCrashing() {
        let store = KeychainKeyStore(service: "GwenMobileTests-\(UUID().uuidString)")
        let outcome = store.read(account: "account-\(UUID().uuidString)")
        XCTAssertFalse(store.save("", account: "empty"))
        if case .blocked(let status) = outcome {
            XCTAssertEqual(KeychainRead.blocked(status: status).isBlocked, true)
            XCTAssertEqual(KeychainRead.blocked(status: status).text, "")
        } else {
            XCTAssertEqual(outcome, .absent)
        }
    }
}
