@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class FilesGapCoverageTests: GwenTestCase {
    func testTheFileBlockNamesEveryExtractionWay() {
        for via in [ExtractionVia.textLayer, .richText, .docx, .ocr, .plain, .none] {
            let withPages = FileTextBlocks.file(name: "a.docx", pages: 3, text: "Inhalt",
                                                via: via, truncated: false)
            XCTAssertTrue(withPages.contains("a.docx"), "\(via)")
            XCTAssertTrue(withPages.contains("Inhalt"), "\(via)")
            let withoutPages = FileTextBlocks.file(name: "a.docx", pages: nil, text: "Inhalt",
                                                   via: via, truncated: true)
            XCTAssertTrue(withoutPages.contains(FileTextBlocks.fileEnd), "\(via)")
        }
        XCTAssertEqual(FileTextBlocks.pageMarked([]), "")
        XCTAssertEqual(FileTextBlocks.pageMarked(["eins"]), "eins")
        XCTAssertTrue(FileTextBlocks.pageMarked(["eins", "zwei"]).contains("eins"))
        XCTAssertTrue(FileTextBlocks.pageMarked(["eins", "zwei"]).contains("zwei"))
        XCTAssertEqual(FileTextBlocks.excerpt("  kurz  ", limit: 100).text, "kurz")
        XCTAssertTrue(FileTextBlocks.excerpt(String(repeating: "x", count: 50), limit: 10).truncated)
    }

    func testTheDocxReaderKeepsTabsAndLineBreaks() {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body><w:p><w:r><w:t>A</w:t><w:tab/><w:t>B</w:t><w:br/><w:t>C</w:t><w:cr/><w:t>D</w:t></w:r></w:p>
        </w:body></w:document>
        """
        XCTAssertEqual(DocxText.text(fromDocumentXML: Data(xml.utf8)), "A\tB\nC\nD")
        let leadingBreak = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body><w:p><w:r><w:br/><w:t>A</w:t></w:r></w:p></w:body></w:document>
        """
        XCTAssertEqual(DocxText.text(fromDocumentXML: Data(leadingBreak.utf8)), "A")
    }

    func testTheDocumentStoreDiscardsStoredFiles() throws {
        let paths = temporaryPaths("files-gap")
        let store = DocumentStore(paths: paths)
        store.prepareDirectories()
        let source = temporaryPaths("files-gap-src").documents.appendingPathComponent("probe.txt")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("text".utf8).write(to: source)
        let stored = try XCTUnwrap(store.store(url: source))
        XCTAssertEqual(store.byteSize(of: stored.file), 4)
        store.discardStored([stored.file])
        XCTAssertFalse(store.fileNames().contains(stored.file))
    }

    func testTheRichTextHelpersReadPlainText() {
        let attributed = NSAttributedString(string: "Hallo Welt")
        XCTAssertEqual(RichTextFile.plainText(of: attributed), "Hallo Welt")
        XCTAssertFalse(RichTextFile.read(url: temporaryPaths("rtf-gap").documents).hasPictures)
    }
}
