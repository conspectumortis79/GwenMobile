@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

private struct EdgeLayout: StoredFileLayout {
    let directory: URL
    let trashDirectory: URL
    let sidecarURL: URL?
    let trashSidecarURL: URL?

    var prefix: String { "edge_" }

    func stored(_ name: String) -> URL { directory.appendingPathComponent(name) }
    func sidecar(of name: String) -> URL? { sidecarURL }
    func trashedSidecar(of name: String) -> URL? { trashSidecarURL }
}

final class FileStorageEdgeTests: GwenTestCase {
    private let manager = FileManager.default

    private func makeFile(_ url: URL, _ bytes: [UInt8] = [1, 2, 3]) throws {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
    }

    func testPrepareReportsAnImpossibleDirectory() throws {
        let blocker = tempDocuments().appendingPathComponent("blocker")
        try Data([0]).write(to: blocker)
        let layout = EdgeLayout(directory: blocker.appendingPathComponent("sub"),
                                trashDirectory: blocker.appendingPathComponent("trash"),
                                sidecarURL: nil, trashSidecarURL: nil)
        FileStorage(layout: layout, fileManager: manager).prepare()
        XCTAssertTrue(manager.fileExists(atPath: blocker.path))
    }

    func testWriteSidecarReportsAnImpossibleTarget() throws {
        let directory = tempDocuments()
        let target = directory.appendingPathComponent("beleg")
        try makeFile(target, [])
        let layout = EdgeLayout(directory: directory, trashDirectory: directory,
                                sidecarURL: target, trashSidecarURL: nil)
        let storage = FileStorage(layout: layout, fileManager: manager)
        try makeFile(storage.url(for: "beleg"))
        storage.writeSidecar("inhalt", for: "beleg")
        XCTAssertTrue(manager.fileExists(atPath: target.path))
    }

    func testMoveToTrashReportsAnImpossibleDestination() throws {
        let directory = tempDocuments()
        let blocker = directory.appendingPathComponent("blocker")
        try Data([0]).write(to: blocker)
        let layout = EdgeLayout(directory: directory, trashDirectory: blocker,
                                sidecarURL: nil, trashSidecarURL: nil)
        let storage = FileStorage(layout: layout, fileManager: manager)
        try makeFile(storage.url(for: "f_alt"))
        XCTAssertTrue(storage.moveToTrash(["f_alt"]).isEmpty)
    }

    func testEmptyTrashReportsAMissingDirectory() {
        let directory = tempDocuments()
        let layout = EdgeLayout(directory: directory,
                                trashDirectory: directory.appendingPathComponent("fehlt"),
                                sidecarURL: nil, trashSidecarURL: nil)
        FileStorage(layout: layout, fileManager: manager).emptyTrash()
        XCTAssertFalse(manager.fileExists(atPath: layout.trashDirectory.path))
    }

    func testCopyReportsAMissingSource() {
        let directory = tempDocuments()
        let layout = EdgeLayout(directory: directory, trashDirectory: directory,
                                sidecarURL: nil, trashSidecarURL: nil)
        let storage = FileStorage(layout: layout, fileManager: manager)
        XCTAssertNil(storage.copy(from: directory.appendingPathComponent("gibt_es_nicht"), as: "f_neu"))
    }

    func testDiscardReportsAnUndeniableFile() throws {
        let directory = tempDocuments()
        let storage = FileStorage(layout: EdgeLayout(directory: directory, trashDirectory: directory,
                                                     sidecarURL: nil, trashSidecarURL: nil),
                                  fileManager: manager)
        try makeFile(storage.url(for: "f_geschuetzt"))
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        storage.discard(["f_geschuetzt"])
        XCTAssertTrue(manager.fileExists(atPath: storage.url(for: "f_geschuetzt").path))
    }

    func testRestoreReportsAnImpossibleDestination() throws {
        let directory = tempDocuments()
        let trash = tempDocuments()
        let layout = EdgeLayout(directory: directory, trashDirectory: trash,
                                sidecarURL: nil, trashSidecarURL: nil)
        let storage = FileStorage(layout: layout, fileManager: manager)
        try makeFile(layout.trashed("t_alt"))
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        storage.restoreFromTrash([TrashedFile(file: "f_neu", trashed: "t_alt")])
        XCTAssertFalse(manager.fileExists(atPath: storage.url(for: "f_neu").path))
    }

    func testNewNameWithoutAnExtensionStaysBare() {
        let layout = EdgeLayout(directory: tempDocuments(), trashDirectory: tempDocuments(),
                                sidecarURL: nil, trashSidecarURL: nil)
        let name = layout.newName("")
        XCTAssertTrue(name.hasPrefix("edge_"))
        XCTAssertFalse(name.contains("."))
    }

    func testWriteSidecarSkipsWhenThereIsNone() throws {
        let directory = tempDocuments()
        let layout = EdgeLayout(directory: directory, trashDirectory: directory,
                                sidecarURL: nil, trashSidecarURL: nil)
        let storage = FileStorage(layout: layout, fileManager: manager)
        let name = layout.newName("txt")
        try makeFile(storage.url(for: name))
        storage.writeSidecar("text", for: name)
        XCTAssertTrue(manager.fileExists(atPath: storage.url(for: name).path))
    }

    func testWriteSidecarReportsADirectoryTarget() throws {
        let directory = tempDocuments()
        let target = directory.appendingPathComponent("sidecar")
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        let layout = EdgeLayout(directory: directory, trashDirectory: directory,
                                sidecarURL: target, trashSidecarURL: nil)
        FileStorage(layout: layout, fileManager: manager).writeSidecar("text", for: "edge_x")
        XCTAssertTrue(manager.fileExists(atPath: target.path))
    }

    func testCopyReplacesAnExistingTarget() throws {
        let directory = tempDocuments()
        let source = directory.appendingPathComponent("quelle")
        try makeFile(source, [1, 2, 3, 4])
        let layout = EdgeLayout(directory: directory, trashDirectory: directory,
                                sidecarURL: nil, trashSidecarURL: nil)
        let storage = FileStorage(layout: layout, fileManager: manager)
        XCTAssertEqual(storage.copy(from: source, as: "edge_ziel"), 4)
        XCTAssertEqual(storage.copy(from: source, as: "edge_ziel"), 4)
    }

    func testRestoreIgnoresAMissingTrashedFile() {
        let directory = tempDocuments()
        let trash = tempDocuments()
        let storage = FileStorage(layout: EdgeLayout(directory: directory, trashDirectory: trash,
                                                     sidecarURL: nil, trashSidecarURL: nil),
                                  fileManager: manager)
        storage.restoreFromTrash([TrashedFile(file: "f_neu", trashed: "gibt_es_nicht")])
        XCTAssertFalse(manager.fileExists(atPath: storage.url(for: "f_neu").path))
    }
}
