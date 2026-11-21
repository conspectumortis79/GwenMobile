@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class AnswerExporterTests: GwenTestCase {
    func testAFencedFileInsideAnAnswerIsExportedAsCodeAndNotAsFences() throws {
        let url = try AnswerExporter(paths: StoragePaths(documents: tempDocuments())).write(
            text: "Tetris:\n\n```html\n<!doctype html>\n<body>x</body>\n```\n\nViel Spaß.",
            sources: [], question: "Tetris?")
        let stored = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(stored.contains("<pre><code>"), stored)
        XCTAssertTrue(stored.contains("&lt;!doctype html&gt;"), stored)
        XCTAssertFalse(stored.contains(CodeText.fence), "eine exportierte Antwort zeigt keine Zäune")
        XCTAssertTrue(stored.contains("Viel Spaß."))
    }

    func testWriteStoresRenderedHTMLNamedAfterTheQuestion() throws {
        let paths = StoragePaths(documents: tempDocuments())
        XCTAssertEqual(paths.answers.path, paths.documents.appendingPathComponent("answers").path)
        let url = try AnswerExporter(paths: paths).write(
            text: "Die **Hauptstadt** ist Paris.\n\n- Ein Punkt\n- Noch einer",
            sources: [Fixtures.source("Beleg", "https://example.org/a", "example.org")],
            question: "Was ist die Hauptstadt von Frankreich?",
            model: "qwen3.8-flash", elapsed: 4.2, time: "13:41")
        XCTAssertEqual(url.lastPathComponent, "Was ist die Hauptstadt von Frankreich.html")
        let stored = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(stored.hasPrefix("<!doctype html>"))
        XCTAssertTrue(stored.contains("<strong>Hauptstadt</strong>"))
        XCTAssertTrue(stored.contains("<ul><li>Ein Punkt</li><li>Noch einer</li></ul>"))
        XCTAssertFalse(stored.contains("**Hauptstadt**"))
        XCTAssertTrue(stored.contains("<h3>" + L.t("web_sources_head") + "</h3>"))
        XCTAssertTrue(stored.contains("<a href=\"https://example.org/a\">Beleg</a>"))
        XCTAssertTrue(stored.contains("<title>Was ist die Hauptstadt von Frankreich?</title>"))
    }

    func testWriteCreatesDirectoriesAndNeverOverwrites() throws {
        let paths = StoragePaths(documents: tempDocuments().appendingPathComponent("tiefer/drin", isDirectory: true))
        let exporter = AnswerExporter(paths: paths)
        let first = try exporter.write(text: "eins", sources: [], question: "Gleiche Frage?")
        let second = try exporter.write(text: "zwei", sources: [], question: "Gleiche Frage?!")
        XCTAssertEqual(first.lastPathComponent, "Gleiche Frage.html")
        XCTAssertEqual(second.lastPathComponent, "Gleiche Frage 2.html")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8).contains("eins"), true)
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8).contains("zwei"), true)
    }

    func testDifferentQuestionsGetDifferentFilesAndLanguageFollowsTheApp() throws {
        let exporter = AnswerExporter(paths: StoragePaths(documents: tempDocuments()))
        L.apply(.de)
        let german = try exporter.write(text: "Antwort", sources: [], question: "Erkläre mir das")
        L.apply(.en)
        let english = try exporter.write(text: "Answer", sources: [], question: "Explain this")
        XCTAssertTrue(try String(contentsOf: german, encoding: .utf8).contains("<html lang=\"de\">"))
        XCTAssertTrue(try String(contentsOf: english, encoding: .utf8).contains("<html lang=\"en\">"))
        XCTAssertEqual(english.lastPathComponent, "Explain this.html")
    }
}
