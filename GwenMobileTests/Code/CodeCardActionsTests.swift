@testable import GwenMobileSystem
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class RecordingCodePresenter: CodeFilePresenting {
    private(set) var presented: [URL] = []
    var failure: Error?

    func present(url: URL) throws {
        if let failure { throw failure }
        presented.append(url)
    }
}

@MainActor
final class RecordingCodeExporter: CodeFileExporting {
    private(set) var exported: [URL] = []
    var failure: Error?

    func export(url: URL) throws {
        if let failure { throw failure }
        exported.append(url)
    }
}

private struct CardFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class CodeCardActionsTests: GwenTestCase {
    private let block = CodeBlock(language: .html,
                                  lines: ["<!doctype html>", "<html>", "<body>Tetris</body>", "</html>"])

    private struct Card {
        let actions: CodeCardActions
        let presenter: RecordingCodePresenter
        let exporter: RecordingCodeExporter
        let code: URL
    }

    private func card(presenter: RecordingCodePresenter = RecordingCodePresenter(),
                      exporter: RecordingCodeExporter = RecordingCodeExporter(),
                      documents: URL? = nil) -> Card {
        let paths = StoragePaths(documents: documents ?? tempDocuments())
        let files = SavedCodeFiles(exporter: CodeFileExporter(paths: paths))
        return Card(actions: CodeCardActions(files: files, presenter: presenter, exporter: exporter),
                    presenter: presenter, exporter: exporter, code: paths.code)
    }

    private func contents(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    func testDownloadingHandsTheBlocksFileToTheFileManagerAndOpensNoShareSheet() throws {
        let card = card()
        XCTAssertEqual(card.actions.download(block, question: "Tetris?"), .nothing)
        XCTAssertEqual(card.exporter.exported.map(\.path), [card.code.appendingPathComponent("Tetris.html").path])
        XCTAssertEqual(try contents(card.code), ["Tetris.html"])
        XCTAssertTrue(card.presenter.presented.isEmpty, "der Download teilt nichts, er fragt nur nach einem Ziel")
    }

    func testDownloadAndShareOfOneBlockStayOneFile() throws {
        let card = card()
        XCTAssertEqual(card.actions.download(block, question: "Tetris?"), .nothing)
        XCTAssertEqual(card.actions.share(block, question: "Tetris?"), .nothing)
        XCTAssertEqual(card.actions.preview(block, question: "Tetris?"),
                       .preview(CodePreviewPage(url: card.code.appendingPathComponent("Tetris.html"))))
        XCTAssertEqual(try contents(card.code), ["Tetris.html"],
                       "drei Knöpfe, eine Datei — kein Tetris 2.html")
        XCTAssertEqual(card.exporter.exported.count, 1)
        XCTAssertEqual(card.presenter.presented.count, 1)
    }

    func testTheDownloadLabelPromisesTheFileManagerInBothLanguages() {
        L.apply(.de)
        XCTAssertEqual(L.t("code_download"), "In Dateien sichern")
        L.apply(.en)
        XCTAssertEqual(L.t("code_download"), "Save to Files")
    }

    func testARefusingFileManagerIsReportedInsteadOfPretendingSuccess() throws {
        let exporter = RecordingCodeExporter()
        exporter.failure = CardFailure(message: "Ablage abgelehnt")
        let card = card(exporter: exporter)
        XCTAssertEqual(card.actions.download(block, question: "Tetris?"), .notice("Ablage abgelehnt"))
        XCTAssertEqual(try contents(card.code), ["Tetris.html"],
                       "die Datei des Blocks bleibt, der Nutzer kann es erneut versuchen")
    }

    func testAMissingWindowForTheFileManagerIsReported() throws {
        let exporter = RecordingCodeExporter()
        exporter.failure = PresenterError.noHost
        let card = card(exporter: exporter)
        XCTAssertEqual(card.actions.download(block, question: "Tetris?"), .notice(L.t("export_unavailable")))
    }

    func testSharingPresentsTheCodeFileAndNeverAsksTheFileManager() throws {
        let card = card()
        XCTAssertEqual(card.actions.share(block, question: "Tetris?"), .nothing)
        XCTAssertEqual(card.presenter.presented.map(\.lastPathComponent), ["Tetris.html"])
        XCTAssertTrue(card.exporter.exported.isEmpty, "teilen bleibt die Freigabe")
    }

    func testPreviewShowsTheStoredCodeFileAndOpensNoSheet() throws {
        let card = card()
        XCTAssertEqual(card.actions.preview(block, question: "Tetris?"),
                       .preview(CodePreviewPage(url: card.code.appendingPathComponent("Tetris.html"))))
        XCTAssertTrue(card.presenter.presented.isEmpty)
        XCTAssertTrue(card.exporter.exported.isEmpty)
    }

    func testRefusingShareDialogIsReportedOnTheNoticeLine() throws {
        let presenter = RecordingCodePresenter()
        presenter.failure = CardFailure(message: "kein Platz")
        let card = card(presenter: presenter)
        XCTAssertEqual(card.actions.share(block, question: "Tetris?"), .notice("kein Platz"))
    }

    func testACodeFolderThatCannotBeUsedIsReportedByEveryAction() throws {
        let blocker = tempDocuments().appendingPathComponent("blocker")
        try "keine ordnerwurzel".write(to: blocker, atomically: true, encoding: .utf8)
        let card = card(documents: blocker)
        for outcome in [card.actions.download(block, question: "Tetris?"), card.actions.share(block, question: "Tetris?"),
                        card.actions.preview(block, question: "Tetris?")] {
            guard case .notice(let note) = outcome else {
                return XCTFail("ein unbenutzbares Ziel muss eine Meldung liefern, kam \(outcome)")
            }
            XCTAssertFalse(note.isEmpty)
        }
        XCTAssertTrue(card.presenter.presented.isEmpty)
        XCTAssertTrue(card.exporter.exported.isEmpty)
    }
}
