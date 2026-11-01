@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import QuickLook
import UIKit
import UniformTypeIdentifiers
import XCTest
import GwenMobileKit

@MainActor
final class FilesLogicGapTests: GwenTestCase {
    func testTheDocumentPresenterDelegates() {
        let presenter = DocumentPresenter.shared
        var picked: [URL] = []
        presenter.onURLs = { picked = $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText], asCopy: true)
        let first = URL(fileURLWithPath: "/tmp/gap-a.txt")
        let second = URL(fileURLWithPath: "/tmp/gap-b.txt")
        presenter.documentPicker(picker, didPickDocumentsAt: [first])
        presenter.documentPicker(picker, didPickDocumentAt: second)
        presenter.documentPickerWasCancelled(picker)
        presenter.close()
        presenter.close()
        XCTAssertEqual(picked, [second])
    }

    func testTheQuickLookPresenter() throws {
        let presenter = QuickLookPresenter.shared
        presenter.present(url: nil, title: nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gap-quicklook.txt")
        try Data("Inhalt".utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        presenter.present(url: url, title: "Notiz")
        let item = FilePreviewItem(url: url, title: "Notiz")
        XCTAssertEqual(item.previewItemURL, url)
        XCTAssertEqual(item.previewItemTitle, "Notiz")
        let controller = QLPreviewController()
        XCTAssertEqual(presenter.numberOfPreviewItems(in: controller), 1)
        XCTAssertNotNil(presenter.previewController(controller, previewItemAt: 0))
    }

    func testTheZipEndOfCentralDirectory() {
        var bytes = Data(repeating: 0, count: 30)
        bytes.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        bytes.append(Data(repeating: 0, count: 20))
        XCTAssertEqual(ZipArchive.endOfCentralDirectory(in: bytes), 30)
        XCTAssertNil(ZipArchive.endOfCentralDirectory(in: Data()))
        XCTAssertNil(ZipArchive.endOfCentralDirectory(in: Data(repeating: 7, count: 40)))
    }
}
