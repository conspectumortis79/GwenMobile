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
        XCTAssertNotNil(renderView(SecureKeyRow(title: "Management-Key", placeholder: "sk-or-…",
                                               key: .constant("mgmt"), onClear: {}), width: 320))
        XCTAssertNotNil(renderView(SecureKeyRow(placeholder: "sk-…", key: .constant("abc"), onClear: {}),
                                   width: 320))
        XCTAssertNotNil(renderView(SecureKeyRow(placeholder: "sk-…", key: .constant(""),
                                             hasStoredKey: true, onClear: {}), width: 320))
        XCTAssertNotNil(renderView(StackedTextField(title: "Basis-URL", placeholder: "https://…/v1",
                                                    monospaced: true, text: .constant("https://x.test/v1")),
                                   width: 320))
        XCTAssertNotNil(renderView(StackedTextField(title: "Name", placeholder: "GwenMobile",
                                                    monospaced: false, text: .constant("")), width: 320))
    }

    func testTheBalanceCardDrawsEveryState() throws {
        let entries = [ProviderBalance.Entry(total: "12,50", currency: "USD",
                                             granted: "2,00", toppedUp: "10,50")]
        let states: [(ProviderBalance?, String?, Bool)] = [
            (nil, nil, false),
            (nil, nil, true),
            (.init(status: .available, entries: entries, limit: "20,00", usage: "7,50"), nil, false),
            (.init(status: .available, entries: [.init(total: "74,75", currency: "$")],
                   purchasedCredits: "100,00", usedCredits: "25,25"), nil, false),
            (.init(status: .unavailable, entries: entries), nil, false),
            (.init(status: .usageOnly,
                   entries: [.init(total: "34,12", currency: "$")], usage: "34,12"), nil, false),
            (nil, "Nicht erreichbar", false),
        ]
        for descriptor in ProviderCatalog.all where descriptor is any AccountBalanceReporting {
            for (balance, error, loading) in states {
                let card = ProviderBalanceCard(descriptor: descriptor, balance: balance, error: error,
                                               updatedAt: Date(timeIntervalSince1970: 0), loading: loading,
                                               canRefresh: true, refresh: {})
                XCTAssertNotNil(renderView(card, width: 320))
            }
        }
        let consoleURL = try XCTUnwrap(QwenCloudDescriptor.billingLink)
        let consoleCard = ProviderConsoleBalanceCard(descriptor: QwenCloudDescriptor(), consoleURL: consoleURL)
        XCTAssertNotNil(renderView(consoleCard, width: 320))
    }

    func testEveryProviderFormDrawsInsideAForm() async throws {
        let settings = AppSettings.shared
        let provider = settings.provider
        let billing = settings.connections.qwenCloud.billing
        let region = settings.connections.qwenCloud.region
        let workspace = settings.connections.qwenCloud.workspace
        for id in ProviderCatalog.all.map(\.id) {
            settings.provider = id
            let controller = mountView(Form { ProviderFormView(settings: settings) },
                                       size: CGSize(width: 390, height: 700))
            try await settleHosted(controller, milliseconds: 250)
            XCTAssertNotNil(controller.view.window)
        }
        settings.provider = provider
        settings.connections.qwenCloud.billing = .payAsYouGo
        settings.connections.qwenCloud.region = .eu
        settings.connections.qwenCloud.workspace = "workspace-1"
        let regional = mountView(Form { ProviderFormView(settings: settings) },
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
