@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class SettingsViewRenderTests: GwenTestCase {
    func testTheWholeSettingsFormDraws() async throws {
        let (store, cleaner) = stagedStoreWithCleaner("settings-view")
        let controller = mountView(SettingsView().environmentObject(store).environmentObject(cleaner),
                                   size: CGSize(width: 390, height: 1400))
        try await settleHosted(controller, milliseconds: 600)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 390, height: 8000)).height, 400)
    }

    func testTheFormDrawsForAnotherProviderAndLanguage() async throws {
        let (store, cleaner) = stagedStoreWithCleaner("settings-view-alt")
        let settings = AppSettings.shared
        let provider = settings.provider
        let language = settings.language
        settings.provider = .openRouter
        settings.language = .de
        let controller = mountView(SettingsView().environmentObject(store).environmentObject(cleaner),
                                   size: CGSize(width: 390, height: 1400))
        try await settleHosted(controller, milliseconds: 600)
        XCTAssertNotNil(controller.view.window)
        settings.provider = provider
        settings.language = language
    }

    func testEverySettingsCategoryDraws() async throws {
        let (store, cleaner) = stagedStoreWithCleaner("settings-categories")
        for category in SettingsCategory.allCases {
            let controller = mountView(SettingsView(initialCategory: category)
                .environmentObject(store).environmentObject(cleaner),
                                       size: CGSize(width: 390, height: 1400))
            try await settleHosted(controller, milliseconds: 350)
            XCTAssertNotNil(controller.view.window, "\(category)")
        }
    }

    func testTheSettingsListPlacesAiModelsBeforeLanguageAndAppearance() {
        XCTAssertEqual(Array(SettingsCategory.allCases.prefix(2)), [.ai, .language])
    }

    func testTheProviderSelectionDraws() async throws {
        let controller = mountView(NavigationStack { ProviderSelectionView() },
                                   size: CGSize(width: 390, height: 900))
        try await settleHosted(controller, milliseconds: 350)
        XCTAssertNotNil(controller.view.window)
    }

    func testTheModelsSectionDrawsInsideAForm() async throws {
        var result: String?
        let binding = Binding(get: { result }, set: { result = $0 })
        let controller = mountView(Form { ModelsSettingsView(testResult: binding) },
                                   size: CGSize(width: 390, height: 900))
        try await settleHosted(controller, milliseconds: 500)
        XCTAssertNotNil(controller.view.window)
    }

    func testTheMusicSectionDrawsInsideAForm() async throws {
        let controller = mountView(Form { MusicSettingsSection(settings: AppSettings.shared) },
                                   size: CGSize(width: 390, height: 700))
        try await settleHosted(controller, milliseconds: 400)
        XCTAssertNotNil(controller.view.window)
    }
}

@MainActor
final class SettingsBalanceRenderTests: GwenTestCase {
    func testTheBalanceSectionDrawsAndRefreshes() async throws {
        let (store, cleaner) = stagedStoreWithCleaner("settings-balance")
        let settings = AppSettings.shared
        let provider = settings.provider
        let key = settings.key(for: .openRouter)
        defer {
            settings.setKey(key, for: .openRouter)
            settings.provider = provider
            MockHTTP.uninstall()
        }
        settings.provider = .openRouter
        settings.setKey("sk-or-balance-probe", for: .openRouter)
        MockHTTP.install { request in
            let path = request.url?.path ?? ""
            if path.contains("credits") {
                return (200, Data(#"{"data":{"total_credits":100,"total_usage":25}}"#.utf8))
            }
            if path.contains("key") {
                return (200, Data(#"{"data":{"limit":20,"usage":5}}"#.utf8))
            }
            return (200, Data("{}".utf8))
        }
        let view = SettingsView(initialCategory: .ai)
        let controller = mountView(view.environmentObject(store).environmentObject(cleaner),
                                   size: CGSize(width: 390, height: 1600))
        try await settleHosted(controller, milliseconds: 800)
        await view.loadBalanceForSettings()
        await view.refreshCurrentBalance()
        XCTAssertNotNil(controller.view.window)
    }
}
