@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import XCTest
import GwenMobileKit

@MainActor
final class HelpCenterViewTests: GwenTestCase {
    func testTheCatalogCoversEveryCategoryWithTranslatedExamples() {
        XCTAssertEqual(HelpCatalog.sections.count, HelpCategory.allCases.count - 1)
        var ids: Set<String> = []
        for section in HelpCatalog.sections {
            XCTAssertNotEqual(section.category, .all)
            XCTAssertGreaterThanOrEqual(section.examples.count, 2)
            for example in section.examples {
                XCTAssertTrue(ids.insert(example.id).inserted)
                XCTAssertNotEqual(example.title, example.titleKey)
                XCTAssertNotEqual(example.detail, example.detailKey)
                XCTAssertFalse(example.symbol.isEmpty)
                XCTAssertEqual(example.text, example.title)
            }
        }
    }

    func testTheCatalogFiltersByCategoryAndSearch() {
        let chat = HelpCatalog.filtered(category: .chat, query: "")
        XCTAssertEqual(chat.map(\.category), [.chat])
        XCTAssertEqual(chat.first?.examples.count,
                       HelpCatalog.sections.first { $0.category == .chat }?.examples.count)

        let playstation = HelpCatalog.filtered(category: .all, query: "playstation")
        XCTAssertEqual(playstation.map(\.category), [.prices])
        XCTAssertEqual(playstation.first?.examples.count, 1)

        XCTAssertTrue(HelpCatalog.filtered(category: .all, query: "zzzz").isEmpty)
    }

    func testTheHelpCenterDrawsItsSections() async throws {
        let store = stagedStore("help-center-view").store
        let view = HelpCenterView(onUseExample: { _ in })
            .environmentObject(store)
        let controller = mountView(view, size: CGSize(width: 390, height: 1400))
        try await settleHosted(controller, milliseconds: 600)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 390, height: 4000)).height, 700)
    }

    func testTheHelpRequestAdvancesTheToken() {
        let before = HelpRequests.shared.token
        HelpRequests.shared.ask()
        XCTAssertEqual(HelpRequests.shared.token, before + 1)
    }
}
