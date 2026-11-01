@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ScanAnswerTests: GwenTestCase {
    func testTheScanAnswersNameTheirStates() {
        XCTAssertFalse(ScanAnswers.cancelled.isEmpty)
        XCTAssertFalse(ScanAnswers.failed.isEmpty)
        XCTAssertFalse(ScanAnswers.unavailable.isEmpty)
        XCTAssertTrue(ScanAnswers.fileName(for: .invoice, date: Date(timeIntervalSince1970: 0)).hasSuffix(".pdf"))
        for kind in ScanKind.allCases {
            XCTAssertFalse(ScanAnswers.fileName(for: kind, date: Date()).isEmpty)
        }
    }
}

final class ScanSaverTests: GwenTestCase {
    private func preparedStore(documents: URL, support: URL) -> DocumentStore {
        let store = DocumentStore(paths: StoragePaths(documents: documents, support: support))
        store.prepareDirectories()
        return store
    }

    func testAFailedDownloadCopyReturnsNoURL() throws {
        let documents = tempDocuments()
        let support = tempDocuments()
        let store = preparedStore(documents: documents, support: support)
        let temporary = documents.appendingPathComponent("quelle.pdf")
        try Data([1, 2, 3]).write(to: temporary)
        let stored = try XCTUnwrap(store.store(url: temporary))
        try Data([0]).write(to: store.paths.downloads)
        let file = AttachedFile(file: stored.file, name: "Rechnung.pdf", kind: .pdf, bytes: stored.bytes,
                                pages: 1, chars: 10, truncated: false, via: .ocr)
        XCTAssertNil(ScanSaver.storeInDownloads(file, documents: store))
    }

    func testAStoreFailureLeavesNoDocument() throws {
        let paths = StoragePaths(documents: tempDocuments(), support: tempDocuments())
        try Data([0]).write(to: paths.files)
        let store = DocumentStore(paths: paths)
        let outcome = ScanWorkflow().store(pages: [FakePicture.make()], kind: .invoice, date: Date(),
                                           documents: store)
        XCTAssertNil(outcome)
    }

    func testUniqueURLCountsUpInsteadOfOverwriting() throws {
        let folder = tempDocuments()
        let existing = folder.appendingPathComponent("Rechnung.pdf")
        try Data().write(to: existing)
        let unique = ScanSaver.uniqueURL(in: folder, name: "Rechnung.pdf")
        XCTAssertEqual(unique.lastPathComponent, "Rechnung-2.pdf")
    }
}
