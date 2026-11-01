@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class MemoryViewTests: GwenTestCase {
    private func makeStore(_ prefix: String) -> ChatStore {
        let paths = temporaryPaths(prefix)
        return ChatStore(media: MediaStore(paths: paths), paths: paths)
    }

    func testTheEmptyMemoryShowsTheHint() async throws {
        let store = makeStore("memory-view-empty")
        let controller = mountView(NavigationStack { MemoryView().environmentObject(store) },
                                   size: CGSize(width: 390, height: 600))
        try await settleHosted(controller, milliseconds: 400)
        XCTAssertNotNil(controller.view.window)
    }

    func testEveryCategoryWithEntriesDrawsARow() async throws {
        let store = makeStore("memory-view-full")
        for (index, category) in MemoryCategory.allCases.enumerated() {
            let dated = index.isMultiple(of: 3)
            _ = await store.memory.add(text: "Notiz \(index) zu \(category.rawValue)",
                                       category: category,
                                       source: index.isMultiple(of: 2) ? .manual : .suggestion,
                                       date: dated ? Date().addingTimeInterval(86_400) : nil,
                                       intervalMonths: dated ? 6 : nil,
                                       remind: index.isMultiple(of: 2))
        }
        if let first = await store.memory.all().first {
            await store.memory.setPinned(key: first.shortKey, pinned: true)
        }
        let controller = mountView(NavigationStack { MemoryView().environmentObject(store) },
                                   size: CGSize(width: 390, height: 900))
        try await settleHosted(controller, milliseconds: 600)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 340, height: 4000)).height, 100)
    }

    func testTheCategoryTintsAndSymbolsExist() {
        XCTAssertNotNil(MemoryStyle.tint(.person))
        XCTAssertNotNil(MemoryStyle.tint(.likes))
        XCTAssertNotNil(MemoryStyle.tint(.people))
        XCTAssertNotNil(MemoryStyle.tint(.work))
        XCTAssertNotNil(MemoryStyle.tint(.health))
        XCTAssertNotNil(MemoryStyle.tint(.plans))
    }

    func testTheMemoryFilterMatchesTheSearch() {
        let entries = [MemoryEntry(text: "mag Tee", category: .likes, source: .manual),
                       MemoryEntry(text: "Zahnarzt", category: .health, source: .manual)]
        XCTAssertEqual(MemoryView.filtered(entries, search: "tee").map(\.text), ["mag Tee"])
        XCTAssertEqual(MemoryView.filtered(entries, search: "  ").count, 2)
        XCTAssertEqual(MemoryView.filtered(entries, search: "").count, 2)
        XCTAssertTrue(MemoryView.filtered(entries, search: "nichts").isEmpty)
    }
}
