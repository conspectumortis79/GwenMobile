@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class MemoryEditorSheetTests: GwenTestCase {
    private func makeStore(_ prefix: String) -> ChatStore {
        let paths = temporaryPaths(prefix)
        return ChatStore(media: MediaStore(paths: paths), paths: paths)
    }

    func testTheNewEntrySheetDraws() async throws {
        let store = makeStore("memory-sheet-new")
        let controller = mountView(NavigationStack {
            MemoryEditorSheet(entry: nil).environmentObject(store)
        }, size: CGSize(width: 390, height: 700))
        try await settleHosted(controller, milliseconds: 400)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100)
    }

    func testTheEditSheetDrawsAReminderAndItsDueLine() async throws {
        let store = makeStore("memory-sheet-remind")
        let entry = MemoryEntry(text: "Zahnarzt", category: .health, dueDate: Date().addingTimeInterval(86_400),
                                remind: true)
        let controller = mountView(NavigationStack {
            MemoryEditorSheet(entry: entry).environmentObject(store)
        }, size: CGSize(width: 390, height: 800))
        try await settleHosted(controller, milliseconds: 400)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100)
    }

    func testTheEditSheetDrawsWithDueDateAndDelete() async throws {
        let store = makeStore("memory-sheet-edit")
        let created = await store.memory.add(text: "mag Tee", category: .likes, source: .manual,
                                             date: Date().addingTimeInterval(-86_400), remind: true)
        let entry = try XCTUnwrap(created?.entry)
        let controller = mountView(NavigationStack {
            MemoryEditorSheet(entry: entry).environmentObject(store)
        }, size: CGSize(width: 390, height: 800))
        try await settleHosted(controller, milliseconds: 400)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100)
    }

    func testTheCommitAndRemoveHelpersChangeTheStore() async throws {
        let store = makeStore("memory-sheet-commit")
        await MemoryEditorSheet.commit(store: store, entry: nil, text: "  mag Kaffee  ",
                                       category: .likes, pinned: true, remind: false)
        let created = await store.memory.all()
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created.first?.text, "Mag Kaffee")
        XCTAssertEqual(created.first?.pinned, true)
        let entry = try XCTUnwrap(created.first)
        await MemoryEditorSheet.commit(store: store, entry: entry, text: "mag grünen Tee",
                                       category: .health, pinned: false, remind: true)
        let updated = await store.memory.all().first
        XCTAssertEqual(updated?.text, "Mag grünen Tee")
        XCTAssertEqual(updated?.category, .health)
        await MemoryEditorSheet.remove(store: store, entry: updated)
        let afterDelete = await store.memory.all()
        XCTAssertTrue(afterDelete.isEmpty)
        await MemoryEditorSheet.commit(store: store, entry: nil, text: "   ", category: .work,
                                       pinned: false, remind: false)
        let afterEmpty = await store.memory.all()
        XCTAssertTrue(afterEmpty.isEmpty)
    }

    func testTheEditSheetDrawsWithAFutureReminderDate() async throws {
        let store = makeStore("memory-sheet-future")
        let created = await store.memory.add(text: "Zahnarzt", category: .health, source: .manual,
                                             date: Date().addingTimeInterval(7 * 86_400), remind: true)
        let entry = try XCTUnwrap(created?.entry)
        let controller = mountView(NavigationStack {
            MemoryEditorSheet(entry: entry).environmentObject(store)
        }, size: CGSize(width: 390, height: 800))
        try await settleHosted(controller, milliseconds: 400)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 390, height: 3000)).height, 100)
    }

    func testTheExportHelperWritesTheFile() throws {
        let url = try MemoryView.exportURL(for: Data(#"{"a":1}"#.utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url), Data(#"{"a":1}"#.utf8))
    }
}
