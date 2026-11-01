@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class ProviderSettingsViewsTests: GwenTestCase {
    func testEveryProviderGlyphAndChoiceDraws() {
        for descriptor in ProviderCatalog.all {
            XCTAssertNotNil(renderView(ProviderGlyphView(glyph: descriptor.glyph), width: 60))
            XCTAssertNotNil(renderView(ProviderChoiceRow(descriptor: descriptor, selected: true, choose: {}),
                                       width: 320))
            XCTAssertNotNil(renderView(ProviderChoiceRow(descriptor: descriptor, selected: false, choose: {}),
                                       width: 320))
            XCTAssertNotNil(renderView(CapabilityChipsRow(capabilities: descriptor.capabilities), width: 320))
        }
    }

    func testTheKeyAndTextRowsCoverEmptyAndFilledState() {
        XCTAssertNotNil(renderView(SecureKeyRow(placeholder: "sk-…", key: .constant(""), onClear: {}), width: 320))
        XCTAssertNotNil(renderView(SecureKeyRow(placeholder: "sk-…", key: .constant("abc"), onClear: {}),
                                   width: 320))
        XCTAssertNotNil(renderView(StackedTextField(title: "Basis-URL", placeholder: "https://…/v1",
                                                    monospaced: true, text: .constant("https://x.test/v1")),
                                   width: 320))
        XCTAssertNotNil(renderView(StackedTextField(title: "Name", placeholder: "GwenMobile",
                                                    monospaced: false, text: .constant("")), width: 320))
    }

    func testEveryProviderFormDrawsInsideAForm() async throws {
        let settings = AppSettings.shared
        let provider = settings.provider
        let billing = settings.connections.qwenCloud.billing
        let region = settings.connections.qwenCloud.region
        let workspace = settings.connections.qwenCloud.workspace
        for id in ProviderCatalog.all.map(\.id) {
            settings.provider = id
            let controller = mountView(Form { ProviderFormView(settings: settings, balance: "12,34 €") },
                                       size: CGSize(width: 390, height: 700))
            try await settleHosted(controller, milliseconds: 250)
            XCTAssertNotNil(controller.view.window)
        }
        settings.provider = provider
        settings.connections.qwenCloud.billing = .payAsYouGo
        settings.connections.qwenCloud.region = .eu
        settings.connections.qwenCloud.workspace = "workspace-1"
        let regional = mountView(Form { ProviderFormView(settings: settings, balance: nil) },
                                 size: CGSize(width: 390, height: 700))
        try await settleHosted(regional, milliseconds: 250)
        let problem = settings.keychainProblem
        settings.keychainProblem = "Schlüssel nicht lesbar"
        XCTAssertNotNil(renderView(ProviderFooterView(settings: settings), width: 320))
        settings.keychainProblem = problem
        settings.connections.qwenCloud.billing = billing
        settings.connections.qwenCloud.region = region
        settings.connections.qwenCloud.workspace = workspace
    }
}

@MainActor
final class HistoryViewRenderTests: GwenTestCase {
    func testTheEmptyHistoryDraws() async throws {
        let (store, cleaner) = stagedStoreWithCleaner("history-empty")
        let controller = mountView(HistoryView().environmentObject(store).environmentObject(cleaner),
                                   size: CGSize(width: 390, height: 700))
        try await settleHosted(controller, milliseconds: 400)
        XCTAssertNotNil(controller.view.window)
    }

    func testTheRowImageCountIncludesGalleryPictures() throws {
        let (store, _) = stagedStoreWithCleaner("history-gallery-count")
        let file = try XCTUnwrap(store.media.storeImageData(Data([1, 2, 3])))
        let id = try XCTUnwrap(store.currentID)
        let picture = WebPicture(file: file, pageURL: "https://example.test/a",
                                 fullURL: "https://example.test/a.jpg", title: "A", domain: "example.test")
        let gallery = PictureGallery(query: "A", pictures: [picture], shown: 1,
                                     nextOffset: 2, exhausted: true)
        store.appendMessage(ChatMessage(role: .assistant, text: "", gallery: gallery), to: id)
        XCTAssertEqual(HistoryView.imageCount(try XCTUnwrap(store.current)), 1)
    }

    func testEveryConversationRowDraws() async throws {
        let (store, cleaner) = stagedStoreWithCleaner("history-full")
        for index in 0..<4 {
            store.newConversation()
            if let id = store.current?.id {
                store.appendMessage(ChatMessage(role: .user, text: "Frage \(index)"),
                                    to: id)
                store.appendMessage(ChatMessage(role: .assistant, text: "Antwort \(index)"),
                                    to: id)
            }
        }
        let controller = mountView(HistoryView().environmentObject(store).environmentObject(cleaner),
                                   size: CGSize(width: 390, height: 900))
        try await settleHosted(controller, milliseconds: 500)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 390, height: 4000)).height, 100)
    }
}
