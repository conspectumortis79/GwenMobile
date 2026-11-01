@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
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
