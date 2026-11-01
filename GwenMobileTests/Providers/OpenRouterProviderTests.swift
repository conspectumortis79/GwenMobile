@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class OpenRouterProviderTests: XCTestCase {
    override func tearDown() {
        HTTP.decorator.set(NoRequestDecoration())
        L.apply(.en)
        super.tearDown()
    }

    func testAttributionHeadersTravelOnlyWithAnAppName() {
        var named = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        OpenRouterAttribution(appName: " GwenMobile ").decorate(&named)
        XCTAssertEqual(named.value(forHTTPHeaderField: "X-OpenRouter-Title"), "GwenMobile")
        XCTAssertEqual(named.value(forHTTPHeaderField: "X-Title"), "GwenMobile")
        XCTAssertEqual(named.value(forHTTPHeaderField: "HTTP-Referer"), OpenRouterAttribution.referer)
        XCTAssertEqual(named.value(forHTTPHeaderField: "X-OpenRouter-App-Visibility"), "hidden")

        var anonymous = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        OpenRouterAttribution(appName: "  ").decorate(&anonymous)
        XCTAssertNil(anonymous.value(forHTTPHeaderField: "X-OpenRouter-Title"))
        XCTAssertNil(anonymous.value(forHTTPHeaderField: "HTTP-Referer"))
    }

    func testTheActiveDecoratorReachesEveryAuthorisedRequest() throws {
        HTTP.decorator.set(OpenRouterAttribution(appName: "Probe"))
        let post = try HTTP.jsonPOST(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                                     key: "k", body: ["model": "m"], timeout: 5)
        XCTAssertEqual(post.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertEqual(post.value(forHTTPHeaderField: "X-OpenRouter-Title"), "Probe")
        let get = HTTP.authorizedGET(url: URL(string: "https://openrouter.ai/api/v1/models")!, key: "k", timeout: 5)
        XCTAssertEqual(get.value(forHTTPHeaderField: "X-Title"), "Probe")
        HTTP.decorator.set(NoRequestDecoration())
        let plain = HTTP.authorizedGET(url: URL(string: "https://x.example/v1/models")!, key: "k", timeout: 5)
        XCTAssertNil(plain.value(forHTTPHeaderField: "X-Title"))
        XCTAssertEqual(plain.value(forHTTPHeaderField: "Authorization"), "Bearer k")
    }

    func testDescriptorBuildsTheAttributionFromTheConnections() {
        var connections = ProviderConnections()
        connections.openRouter.appName = "Meine App"
        let decorator = OpenRouterDescriptor().requestDecorator(connections) as? OpenRouterAttribution
        XCTAssertEqual(decorator, OpenRouterAttribution(appName: "Meine App"))
        XCTAssertTrue(QwenCloudDescriptor().requestDecorator(connections) is NoRequestDecoration)
    }

    func testKeyInfoDecodesTheDocumentedPayload() throws {
        let json = """
        {"data":{"label":"sk-or-v1-au7...890","limit":100,"limit_remaining":74.5,"usage":25.5,"is_free_tier":false}}
        """
        let info = try JSONDecoder().decode(OpenRouterKeyInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.data.limitRemaining, 74.5)
        XCTAssertEqual(info.data.usage, 25.5)
    }

    func testBalanceTextPrefersTheRemainingLimitAndFormatsPerLanguage() throws {
        let limited = OpenRouterKeyInfo(data: .init(limitRemaining: 12.4, usage: 87.6))
        L.apply(.de)
        XCTAssertEqual(limited.balanceText, "12,40 $ verbleibend")
        L.apply(.en)
        XCTAssertEqual(limited.balanceText, "12.40 $ remaining")
        let unlimited = OpenRouterKeyInfo(data: .init(limitRemaining: nil, usage: 3))
        XCTAssertEqual(unlimited.balanceText, "3.00 $ used")
    }

    func testKeyInfoRequestTargetsTheKeyEndpoint() throws {
        let request = try OpenRouterAPI.keyInfoRequest(key: "sk-or-1")
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-1")
        XCTAssertNil(request.httpBody)
    }

    func testDescriptorHasAFixedURLAndNoRealtimeAudio() {
        let descriptor = OpenRouterDescriptor()
        var connections = ProviderConnections()
        connections.openRouter.appName = "x"
        XCTAssertEqual(descriptor.baseURL(connections), OpenRouterAPI.baseURL)
        XCTAssertTrue(descriptor.usesPresetURL(connections))
        XCTAssertFalse(descriptor.isConfigured(connections, key: ""))
        XCTAssertTrue(descriptor.isConfigured(connections, key: "sk-or-1"))
        XCTAssertEqual(descriptor.capabilities.vision, .available)
        XCTAssertEqual(descriptor.capabilities.image, .available)
        XCTAssertEqual(descriptor.capabilities.videoGeneration, .available)
        XCTAssertTrue(descriptor.imageBackend is OpenRouterImageBackend)
        XCTAssertTrue(descriptor.videoGenerationBackend is OpenRouterVideoBackend)
        XCTAssertTrue(descriptor.modelLister is OpenRouterModelLister)
        XCTAssertEqual(descriptor.keyPlaceholder(connections), "sk-or-v1-…")
        XCTAssertTrue((descriptor as any ProviderDescriptor) is any AccountBalanceReporting)
        XCTAssertFalse((QwenCloudDescriptor() as any ProviderDescriptor) is any AccountBalanceReporting)
    }
}
