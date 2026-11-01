@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class QwenCloudProviderTests: XCTestCase {
    func testTokenPlanIgnoresRegionAndWorkspace() {
        let config = QwenCloudConfig(billing: .tokenPlan, region: .eu, workspace: "ws")
        XCTAssertEqual(config.baseURL, QwenEndpoints.tokenPlan)
        XCTAssertFalse(config.showsRegion)
        XCTAssertFalse(config.showsWorkspace)
        XCTAssertTrue(config.isComplete)
    }

    func testPayAsYouGoRegionsMapToTheirDashScopeHosts() {
        XCTAssertEqual(QwenCloudConfig(billing: .payAsYouGo, region: .international).baseURL,
                       "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(QwenCloudConfig(billing: .payAsYouGo, region: .us).baseURL,
                       "https://dashscope-us.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(QwenCloudConfig(billing: .payAsYouGo, region: .china).baseURL,
                       "https://dashscope.aliyuncs.com/compatible-mode/v1")
    }

    func testEuRegionInsertsTheWorkspaceAndFallsBackToThePlaceholder() {
        let filled = QwenCloudConfig(billing: .payAsYouGo, region: .eu, workspace: " llm-abc ")
        XCTAssertEqual(filled.baseURL, "https://llm-abc.eu-central-1.maas.aliyuncs.com/compatible-mode/v1")
        XCTAssertTrue(filled.showsRegion)
        XCTAssertTrue(filled.showsWorkspace)
        XCTAssertTrue(filled.isComplete)
        let empty = QwenCloudConfig(billing: .payAsYouGo, region: .eu)
        XCTAssertEqual(empty.baseURL, "https://<WorkspaceId>.eu-central-1.maas.aliyuncs.com/compatible-mode/v1")
        XCTAssertFalse(empty.isComplete)
    }

    func testEveryRegionAndBillingCarriesItsOwnLabel() {
        for region in QwenRegion.allCases {
            XCTAssertFalse(region.id.isEmpty)
            XCTAssertFalse(region.labelKey.isEmpty)
            XCTAssertFalse(region.label.isEmpty)
        }
        for billing in QwenBilling.allCases {
            XCTAssertFalse(billing.id.isEmpty)
            XCTAssertFalse(billing.labelKey.isEmpty)
            XCTAssertFalse(billing.label.isEmpty)
        }
    }

    func testEveryDerivedURLRoundTripsThroughTheMatcher() {
        for region in QwenRegion.allCases {
            let config = QwenCloudConfig(billing: .payAsYouGo, region: region,
                                         workspace: region.needsWorkspace ? "llm-xyz" : "")
            XCTAssertEqual(QwenEndpoints.config(matching: config.baseURL), config, "\(region)")
        }
        XCTAssertEqual(QwenEndpoints.config(matching: QwenEndpoints.tokenPlan + "/"), QwenCloudConfig())
        XCTAssertEqual(QwenEndpoints.config(matching: QwenCloudConfig(billing: .payAsYouGo, region: .eu).baseURL),
                       QwenCloudConfig(billing: .payAsYouGo, region: .eu, workspace: ""))
    }

    func testForeignURLsDoNotMatch() {
        XCTAssertNil(QwenEndpoints.config(matching: "https://api.openai.com/v1"))
        XCTAssertNil(QwenEndpoints.config(matching: "https://a/b.eu-central-1.maas.aliyuncs.com/compatible-mode/v1"))
        XCTAssertNil(QwenEndpoints.config(matching: ""))
    }

    func testDescriptorNeedsKeyAndCompleteConfig() {
        let descriptor = QwenCloudDescriptor()
        var connections = ProviderConnections()
        XCTAssertFalse(descriptor.isConfigured(connections, key: ""))
        XCTAssertTrue(descriptor.isConfigured(connections, key: "sk-1"))
        connections.qwenCloud = QwenCloudConfig(billing: .payAsYouGo, region: .eu)
        XCTAssertFalse(descriptor.isConfigured(connections, key: "sk-1"))
        XCTAssertFalse(descriptor.usesPresetURL(connections))
        connections.qwenCloud.workspace = "llm-1"
        XCTAssertTrue(descriptor.isConfigured(connections, key: "sk-1"))
        connections.qwenCloud = QwenCloudConfig()
        XCTAssertTrue(descriptor.usesPresetURL(connections))
    }

    func testDescriptorOffersEveryFeatureWithoutBakingInModelIDs() {
        let descriptor = QwenCloudDescriptor()
        for feature in ProviderFeature.allCases {
            XCTAssertEqual(descriptor.capabilities[feature], .available, "\(feature)")
        }
        XCTAssertTrue(descriptor.defaultProfile.chatModel.isEmpty)
        XCTAssertTrue(descriptor.defaultProfile.visionModel.isEmpty)
        XCTAssertTrue(descriptor.defaultProfile.imageModel.isEmpty)
        XCTAssertTrue(descriptor.defaultProfile.videoModel.isEmpty)
        XCTAssertTrue(descriptor.defaultProfile.videoGenerationModel.isEmpty)
        XCTAssertTrue(descriptor.defaultProfile.videoGenerationModels.isEmpty)
        XCTAssertNotNil(descriptor.videoGenerationBackend)
        XCTAssertNotNil(OpenAICompatibleDescriptor().videoGenerationBackend)
        XCTAssertNotNil(OpenRouterDescriptor().videoGenerationBackend)
        XCTAssertEqual(descriptor.keychainAccount, "qwencloud_api_key")
        XCTAssertNotNil(descriptor.consoleLink)
        XCTAssertFalse(descriptor.consoleLinkTitle.isEmpty)
    }
}
