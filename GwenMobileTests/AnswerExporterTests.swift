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

    private let fileNamePattern = /^gwen-\d{4}-\d{2}-\d{2}-\d{6}\.md$/

    func testFileNameNeedsNoEscapingAndChangesEverySecond() {
        let first = AnswerExporter.fileName(date: Date(timeIntervalSince1970: 1_800_000_000))
        let second = AnswerExporter.fileName(date: Date(timeIntervalSince1970: 1_800_000_061))
        XCTAssertNotNil(first.wholeMatch(of: fileNamePattern), first)
        XCTAssertNotNil(second.wholeMatch(of: fileNamePattern), second)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.contains(" "))
        XCTAssertFalse(first.contains("/"))
        XCTAssertTrue(first.hasSuffix(".md"))
    }

    func testDocumentKeepsTheAnswerUntouchedWithoutSources() {
        let document = AnswerExporter.document(text: "  Hallo **Welt**\nmit Zeilenumbruch\n\n\n",
                                              sources: [], heading: "Quellen")
        XCTAssertEqual(document, "Hallo **Welt**\nmit Zeilenumbruch\n")
    }

    func testDocumentAppendsNumberedSourceLinks() {
        let sources = [source("Startseite", "https://qwen.ai/home", "qwen.ai"),
                       source("   ", "https://swift.org", "swift.org"),
                       source("Doku", "https://developer.apple.com/x", "developer.apple.com")]
        let document = AnswerExporter.document(text: "Antwort", sources: sources, heading: "Quellen")
        let expected = """
        Antwort

        ## Quellen
        1. [Startseite](https://qwen.ai/home)
        2. [swift.org](https://swift.org)
        3. [Doku](https://developer.apple.com/x)

        """
        XCTAssertEqual(document, expected)
    }

    func testWriteStoresUTF8MarkdownInsideTheAnswersFolder() throws {
        let paths = StoragePaths(documents: tempDocuments())
        XCTAssertEqual(paths.answers.path, paths.documents.appendingPathComponent("answers").path)
        let url = try AnswerExporter(paths: paths).write(
            text: "Grüße, Πάντα ☕",
            sources: [source("Beleg", "https://example.org/a", "example.org")],
            date: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(url.deletingLastPathComponent().path, paths.answers.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8),
                       "Grüße, Πάντα ☕\n\n## Quellen\n1. [Beleg](https://example.org/a)\n")
    }

    func testWriteCreatesMissingDirectoriesAndNeverOverwrites() throws {
        let paths = StoragePaths(documents: tempDocuments().appendingPathComponent("tiefer/drin", isDirectory: true))
        let exporter = AnswerExporter(paths: paths)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try exporter.write(text: "eins", sources: [], date: base)
        let second = try exporter.write(text: "zwei", sources: [], date: base.addingTimeInterval(3))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "eins\n")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "zwei\n")
    }

    func testWriteUsesCurrentLanguageForTheSourceHeading() throws {
        let exporter = AnswerExporter(paths: StoragePaths(documents: tempDocuments()))
        let german = try exporter.write(text: "Antwort",
                                        sources: [source("T", "https://a.test", "a.test")],
                                        date: Date(timeIntervalSince1970: 1_800_000_000))
        L.apply(.en)
        let english = try exporter.write(text: "Answer",
                                         sources: [source("T", "https://a.test", "a.test")],
                                         date: Date(timeIntervalSince1970: 1_800_000_001))
        L.apply(.de)
        XCTAssertTrue(try String(contentsOf: german, encoding: .utf8).contains("## Quellen\n"))
        XCTAssertTrue(try String(contentsOf: english, encoding: .utf8).contains("## Sources\n"))
    }
}
