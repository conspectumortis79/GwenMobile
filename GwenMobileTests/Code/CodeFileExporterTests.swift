@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class CodeFileExporterTests: GwenTestCase {
    private let block = CodeBlock(language: .html,
                                 lines: ["<!doctype html>", "<html>", "<body>Tetris</body>", "</html>"])

    private func paths() -> StoragePaths { StoragePaths(documents: tempDocuments()) }

    func testTheCodeFileIsWrittenIntoItsOwnFolderNamedAfterTheQuestion() throws {
        let paths = paths()
        XCTAssertEqual(paths.code.deletingLastPathComponent().path, paths.documents.path,
                       "Code bleibt im sichtbaren Documents-Ordner wie die Antworten")
        let url = try CodeFileExporter(paths: paths).write(block, question: "Programmiere mir Tetris als HTML")
        XCTAssertEqual(url.lastPathComponent, "Programmiere mir Tetris als HTML.html")
        let stored = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(stored, block.code + "\n")
        XCTAssertFalse(stored.contains(CodeText.fence), "die Datei enthält Code, kein Markdown")
    }

    func testTheExtensionFollowsTheBlockAndOnlyItsOwnCodeIsWritten() throws {
        let python = CodeBlock(language: .python, lines: ["print('hallo')"])
        let url = try CodeFileExporter(paths: paths()).write(python, question: "Zähle Dateien")
        XCTAssertEqual(url.pathExtension, "py")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "print('hallo')\n")
    }

    func testADuplicateNameBecomesASecondFileInsteadOfOverwriting() throws {
        let exporter = CodeFileExporter(paths: paths())
        let first = try exporter.write(block, question: "Tetris?", date: Date(timeIntervalSince1970: 1))
        let second = try exporter.write(block, question: "Tetris?!", date: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(first.lastPathComponent, "Tetris.html")
        XCTAssertEqual(second.lastPathComponent, "Tetris 2.html")
    }

    func testAFolderThatDoesNotExistYetIsCreatedOnTheWayIn() throws {
        let paths = StoragePaths(documents: tempDocuments().appendingPathComponent("tiefer/code",
                                                                                  isDirectory: true))
        let url = try CodeFileExporter(paths: paths).write(block, question: "Tetris?")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSavedCodeFilesWritesOnceAndReusesItsOwnFile() throws {
        let exporter = CodeFileExporter(paths: paths())
        let files = SavedCodeFiles(exporter: exporter)
        let first = try files.url(for: block, question: "Tetris?")
        let again = try files.url(for: block, question: "Tetris?")
        XCTAssertEqual(first.path, again.path)
        try FileManager.default.removeItem(at: first)
        let rewritten = try files.url(for: block, question: "Tetris?")
        XCTAssertEqual(rewritten.path, first.path,
                       "ein gelöschtes Stück Code schreibt unter seinem Namen neu, statt ins Leere zu zeigen")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rewritten.path))
    }

    func testChangedCodeIsNeverMixedUpWithTheStoredVersion() throws {
        let files = SavedCodeFiles(exporter: CodeFileExporter(paths: paths()))
        let original = try files.url(for: block, question: "Tetris?")
        let changed = CodeBlock(language: .html, lines: block.lines + ["<!-- neu -->"])
        let grown = try files.url(for: changed, question: "Tetris?")
        XCTAssertNotEqual(original.path, grown.path)
        XCTAssertEqual(try String(contentsOf: grown, encoding: .utf8), changed.code + "\n")
    }

    func testTheRememberedListKeepsOnlyTheNewestFiles() throws {
        let files = SavedCodeFiles(exporter: CodeFileExporter(paths: paths()))
        var blocks: [CodeBlock] = []
        var urls: [URL] = []
        for index in 0..<SavedCodeFiles.capacity {
            let note = CodeBlock(language: .text, lines: ["zeile \(index)"])
            blocks.append(note)
            urls.append(try files.url(for: note, question: "Notiz"))
        }
        let newest = CodeBlock(language: .text, lines: ["zeile \(SavedCodeFiles.capacity)"])
        let newestURL = try files.url(for: newest, question: "Notiz")
        XCTAssertEqual(urls.count, SavedCodeFiles.capacity)
        XCTAssertEqual(try files.url(for: newest, question: "Notiz").path, newestURL.path)
        XCTAssertNotEqual(try files.url(for: blocks[0], question: "Notiz").path, urls[0].path,
                          "der älteste Block ist vergessen und schreibt eine neue Datei")
    }
}
