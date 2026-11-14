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
        XCTAssertEqual(info.data.limit, 100)
        XCTAssertEqual(info.data.limitRemaining, 74.5)
        XCTAssertEqual(info.data.usage, 25.5)
    }

    func testProviderBalanceMapsRemainingLimitUsageAndTheEmptyState() {
        L.apply(.en)
        let limited = OpenRouterKeyInfo(data: .init(limit: 20, limitRemaining: 12.4, usage: 7.6))
        let balance = limited.providerBalance
        XCTAssertEqual(balance.status, .available)
        XCTAssertEqual(balance.entries, [.init(total: "12.40", currency: "$")])
        XCTAssertEqual(balance.limit, "20.00")
        XCTAssertEqual(balance.usage, "7.60")

        let exhausted = OpenRouterKeyInfo(data: .init(limit: 20, limitRemaining: 0, usage: 20))
        XCTAssertEqual(exhausted.providerBalance.status, .unavailable)

        let unlimited = OpenRouterKeyInfo(data: .init(limitRemaining: nil, usage: 3))
        XCTAssertEqual(unlimited.providerBalance.status, .usageOnly)
        XCTAssertEqual(unlimited.providerBalance.entries, [.init(total: "3.00", currency: "$")])
        XCTAssertNil(unlimited.providerBalance.limit)
        XCTAssertEqual(unlimited.providerBalance.usage, "3.00")
    }

    func testCreditsDecodePurchasedUsedAndTheRemainingAmount() throws {
        let json = #"{"data":{"total_credits":100.5,"total_usage":25.75}}"#
        let credits = try JSONDecoder().decode(OpenRouterCredits.self, from: Data(json.utf8))
        XCTAssertEqual(credits.data.totalCredits, 100.5)
        XCTAssertEqual(credits.data.totalUsage, 25.75)
        XCTAssertEqual(credits.remaining, 74.75)
        let balance = credits.providerBalance
        XCTAssertEqual(balance.status, .available)
        XCTAssertEqual(balance.entries, [.init(total: OpenRouterAPI.dollars(74.75), currency: "$")])
        XCTAssertEqual(balance.purchasedCredits, OpenRouterAPI.dollars(100.5))
        XCTAssertEqual(balance.usedCredits, OpenRouterAPI.dollars(25.75))
        XCTAssertNil(balance.limit)
        XCTAssertNil(balance.usage)
    }

    func testCreditsClampAnOverdraftToZeroAndBecomeUnavailable() {
        let credits = OpenRouterCredits(data: .init(totalCredits: 10, totalUsage: 12.5))
        XCTAssertEqual(credits.remaining, 0)
        XCTAssertEqual(credits.providerBalance.status, .unavailable)
        XCTAssertEqual(credits.providerBalance.entries.first?.total, OpenRouterAPI.dollars(0))
    }

    func testCreditsRequestTargetsTheCreditsEndpoint() throws {
        let request = try OpenRouterAPI.creditsRequest(key: "mgmt")
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/credits")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mgmt")
        XCTAssertNil(request.httpBody)
    }

    func testAccountBalancePrefersCreditsAndFallsBackToKeyInfo() async {
        MockHTTP.install { request in
            if request.url?.path == "/api/v1/credits" {
                return (200, Data(#"{"data":{"total_credits":50,"total_usage":10}}"#.utf8))
            }
            return (200, Data(#"{"data":{"limit_remaining":25,"usage":5}}"#.utf8))
        }
        defer { MockHTTP.uninstall() }
        let credits = try? await OpenRouterDescriptor().accountBalance(key: "mgmt")
        XCTAssertEqual(credits?.purchasedCredits, OpenRouterAPI.dollars(50))
        XCTAssertEqual(credits?.entries.first?.total, OpenRouterAPI.dollars(40))

        MockHTTP.install { request in
            if request.url?.path == "/api/v1/credits" {
                return (403, Data(#"{"error":{"code":403,"message":"Only management keys can perform this operation"}}"#.utf8))
            }
            return (200, Data(#"{"data":{"limit_remaining":25,"usage":5}}"#.utf8))
        }
        let fallback = try? await OpenRouterDescriptor().accountBalance(key: "chat")
        XCTAssertNil(fallback?.purchasedCredits)
        XCTAssertEqual(fallback?.entries.first?.total, OpenRouterAPI.dollars(25))
    }

    func testKeyInfoRequestTargetsTheKeyEndpoint() throws {
        let request = try OpenRouterAPI.keyInfoRequest(key: "sk-or-1")
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-1")
        XCTAssertNil(request.httpBody)
        XCTAssertNotNil(OpenRouterDescriptor.managementKeyLink)
        XCTAssertEqual(OpenRouterDescriptor.creditsLink?.absoluteString,
                       "https://openrouter.ai/settings/credits")
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
        XCTAssertEqual(descriptor.consoleLinkTitle, L.t("openrouter_create_key"))
        XCTAssertEqual(descriptor.keyPlaceholder(connections), "sk-or-v1-…")
        XCTAssertTrue((descriptor as any ProviderDescriptor) is any AccountBalanceReporting)
        XCTAssertFalse((QwenCloudDescriptor() as any ProviderDescriptor) is any AccountBalanceReporting)
    }
}
