import XCTest
@testable import GwenMobile

@MainActor
final class AnswerExporterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    private func tempDocuments() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func source(_ title: String, _ url: String, _ domain: String) -> WebSource {
        WebSource(title: title, url: url, domain: domain)
    }

    func testTitleIsTheQuestionWithoutPunctuation() {
        XCTAssertEqual(AnswerExporter.title(from: "Wie viele Arbeitslose gab es?!"),
                       "Wie viele Arbeitslose gab es")
        XCTAssertEqual(AnswerExporter.title(from: "Erkläre „Klima\u{2009}–\u{2009}erwärmung\" bitte! 🌍"),
                       "Erkläre Klima erwärmung bitte")
        XCTAssertEqual(AnswerExporter.title(from: "   "), "")
        XCTAssertEqual(AnswerExporter.title(from: nil), "")
    }

    func testTitleKeepsTheFirstWordsOnly() {
        let long = "a b c d e f g h i j k l"
        XCTAssertEqual(AnswerExporter.title(from: long), "a b c d e f g h i")
        XCTAssertEqual(AnswerExporter.title(from: long).split(separator: " ").count,
                       AnswerExporter.maxTitleWords)
    }

    func testFileNameIsTheQuestionAndFallsBackToTheTimestamp() {
        XCTAssertEqual(AnswerExporter.fileName(question: "Was ist die Hauptstadt von Frankreich?",
                                               date: Date(timeIntervalSince1970: 1_800_000_000)),
                       "Was ist die Hauptstadt von Frankreich.html")
        let fallback = AnswerExporter.fileName(question: "!!! ???", date: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(fallback.hasPrefix("antwort-"))
        XCTAssertTrue(fallback.hasSuffix(".html"))
        XCTAssertNotNil(fallback.wholeMatch(of: /^antwort-\d{4}-\d{2}-\d{2}-\d{6}\.html$/), fallback)
    }

    func testWriteStoresRenderedHTMLNamedAfterTheQuestion() throws {
        let paths = StoragePaths(documents: tempDocuments())
        XCTAssertEqual(paths.answers.path, paths.documents.appendingPathComponent("answers").path)
        let url = try AnswerExporter(paths: paths).write(
            text: "Die **Hauptstadt** ist Paris.\n\n- Ein Punkt\n- Noch einer",
            sources: [source("Beleg", "https://example.org/a", "example.org")],
            question: "Was ist die Hauptstadt von Frankreich?",
            model: "qwen3.8-flash", elapsed: 4.2, time: "13:41")
        XCTAssertEqual(url.lastPathComponent, "Was ist die Hauptstadt von Frankreich.html")
        let stored = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(stored.hasPrefix("<!doctype html>"))
        XCTAssertTrue(stored.contains("<strong>Hauptstadt</strong>"))
        XCTAssertTrue(stored.contains("<ul><li>Ein Punkt</li><li>Noch einer</li></ul>"))
        XCTAssertFalse(stored.contains("**Hauptstadt**"))
        XCTAssertFalse(stored.contains("Gefundene Quellen"))
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
        let german = try exporter.write(text: "Antwort", sources: [], question: "Erkläre mir das")
        L.apply(.en)
        let english = try exporter.write(text: "Answer", sources: [], question: "Explain this")
        L.apply(.de)
        XCTAssertTrue(try String(contentsOf: german, encoding: .utf8).contains("<html lang=\"de\">"))
        XCTAssertTrue(try String(contentsOf: english, encoding: .utf8).contains("<html lang=\"en\">"))
        XCTAssertEqual(english.lastPathComponent, "Explain this.html")
    }
}
