@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class DeepSeekProviderTests: XCTestCase {
    override func tearDown() {
        HTTP.decorator.set(NoRequestDecoration())
        L.apply(.en)
        super.tearDown()
    }

    func testDescriptorPinsTheDocumentedURLAndNeedsOnlyAKey() {
        let descriptor = DeepSeekDescriptor()
        let connections = ProviderConnections()
        XCTAssertEqual(descriptor.baseURL(connections), "https://api.deepseek.com")
        XCTAssertEqual(descriptor.baseURL(connections), DeepSeekAPI.baseURL)
        XCTAssertFalse(descriptor.isConfigured(connections, key: ""))
        XCTAssertTrue(descriptor.isConfigured(connections, key: "sk-deep"))
        XCTAssertTrue(descriptor.usesPresetURL(connections))
        XCTAssertEqual(descriptor.keychainAccount, "deepseek_api_key")
        XCTAssertNotNil(descriptor.consoleLink)
        XCTAssertFalse(descriptor.consoleLinkTitle.isEmpty)
        XCTAssertFalse(descriptor.title.isEmpty)
        XCTAssertFalse(descriptor.subtitle.isEmpty)
        XCTAssertFalse(descriptor.footer.isEmpty)
        XCTAssertFalse(descriptor.modelsFooter.isEmpty)
    }

    func testDescriptorShipsNoModelIDsAndTheDeepSeekCapabilities() {
        let descriptor = DeepSeekDescriptor()
        let connections = ProviderConnections()
        XCTAssertEqual(descriptor.capabilities.chat, .available)
        XCTAssertEqual(descriptor.capabilities.vision, .probed)
        XCTAssertEqual(descriptor.capabilities.image, .unavailable)
        XCTAssertTrue(descriptor.defaultProfile.chatModel.isEmpty)
        XCTAssertEqual(descriptor.thinkingEncoding, .openAI)
        XCTAssertTrue(descriptor.modelDiscoverer is DeepSeekModelCatalog)
        XCTAssertTrue(descriptor.modelLister is OpenAIModelLister)
        XCTAssertNil(descriptor.imageBackend)
        XCTAssertTrue(descriptor.requestDecorator(connections) is NoRequestDecoration)
        XCTAssertEqual(descriptor.keyPlaceholder(connections), "sk-…")
        XCTAssertTrue((descriptor as any ProviderDescriptor) is any AccountBalanceReporting)
    }

    func testChatRequestTargetsTheDocumentedEndpointAndCarriesReasoningEffort() throws {
        let request = try QwenAPI.makeRequest(baseURL: DeepSeekAPI.baseURL, key: "sk-deep",
                                              model: "deepseek-flash",
                                              messages: [ChatMessage(role: .user, text: "Hallo")],
                                              imageData: [], stream: true,
                                              thinking: .suppressing(.openAI))
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-deep")
        let object = try requestObject(request)
        XCTAssertEqual(object["model"] as? String, "deepseek-flash")
        XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertEqual(object["reasoning_effort"] as? String, "none")
        XCTAssertNil(object["enable_thinking"])
    }

    func testBalanceDecodesTheDocumentedPayloadAndFormatsPerLanguage() throws {
        let json = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"}]}"#
        let balance = try JSONDecoder().decode(DeepSeekBalance.self, from: Data(json.utf8))
        XCTAssertTrue(balance.isAvailable)
        XCTAssertEqual(balance.balanceInfos.first?.currency, "CNY")
        XCTAssertEqual(balance.balanceInfos.first?.totalBalance, "110.00")
        L.apply(.de)
        XCTAssertEqual(balance.text, "110.00 CNY verfügbar")
        L.apply(.en)
        XCTAssertEqual(balance.text, "110.00 CNY available")
    }

    func testBalanceJoinsSeveralCurrenciesAndFallsBackToTheNotice() {
        L.apply(.en)
        let both = DeepSeekBalance(isAvailable: true, balanceInfos: [
            .init(currency: "USD", totalBalance: "2.00"),
            .init(currency: "CNY", totalBalance: "14.00"),
        ])
        XCTAssertEqual(both.text, "2.00 USD available · 14.00 CNY available")
        XCTAssertEqual(DeepSeekBalance(isAvailable: false, balanceInfos: both.balanceInfos).text,
                       L.t("deepseek_no_balance"))
        XCTAssertEqual(DeepSeekBalance(isAvailable: true, balanceInfos: []).text,
                       L.t("deepseek_no_balance"))
    }

    func testBalanceRequestTargetsTheDocumentedEndpoint() throws {
        let request = try DeepSeekAPI.balanceRequest(key: "sk-deep")
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/user/balance")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-deep")
        XCTAssertEqual(request.timeoutInterval, APITimeout.modelsRequest)
        XCTAssertNil(request.httpBody)
    }

    private func requestObject(_ request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}
