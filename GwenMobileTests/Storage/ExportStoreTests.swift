@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ExportStoreTests: GwenTestCase {
    func testCountedFilesAndDiscardTrashedWork() throws {
        let paths = StoragePaths(documents: tempDocuments(), support: tempDocuments())
        let store = ExportStore(paths: paths)
        store.prepareDirectories()
        XCTAssertEqual(ExportLayout(paths: paths, folder: .answers).prefix, "")
        let bare = TrashedExport(file: "f", trashed: "t", folder: .answers)
        XCTAssertEqual(bare.bytes, 0)
        try Data([1, 2, 3]).write(to: paths.answers.appendingPathComponent("antwort.html"))
        XCTAssertEqual(store.countedFiles(), 1)
        XCTAssertEqual(store.countedBytes(), 3)
        let trashed = store.moveAllToTrash()
        XCTAssertEqual(trashed.count, 1)
        XCTAssertEqual(trashed.first?.bytes, 3)
        XCTAssertEqual(store.countedFiles(), 0)
        store.discardTrashed(trashed)
        let stillThere = FileManager.default.fileExists(
            atPath: paths.trash.appendingPathComponent(trashed[0].trashed).path)
        XCTAssertFalse(stillThere)
    }
}
