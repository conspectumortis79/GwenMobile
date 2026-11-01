@testable import GwenMobileFeatureCore
import XCTest
import Compression
import GwenMobileKit

enum TestZip {
    static func archive(_ entries: [(name: String, data: Data, deflate: Bool)]) -> Data {
        var payload = Data()
        var central = Data()
        for entry in entries {
            let method: UInt16 = entry.deflate ? 8 : 0
            let stored = entry.deflate ? (deflated(entry.data) ?? entry.data) : entry.data
            let offset = payload.count
            payload.append(localHeader(name: entry.name, method: method,
                                       compressed: stored.count, uncompressed: entry.data.count))
            payload.append(contentsOf: entry.name.utf8)
            payload.append(stored)
            central.append(centralHeader(name: entry.name, method: method,
                                         compressed: stored.count, uncompressed: entry.data.count,
                                         offset: offset))
            central.append(contentsOf: entry.name.utf8)
        }
        var archive = payload
        let centralOffset = archive.count
        archive.append(central)
        archive.append(endRecord(count: entries.count, centralOffset: centralOffset,
                                 centralSize: central.count))
        return archive
    }

    static func deflated(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = max(data.count * 2, 256)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let destination = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { source -> Int in
                guard let source = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(destination, capacity, source, data.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return Data(output.prefix(written))
    }

    private static func sharedTail(method: UInt16, compressed: Int, uncompressed: Int,
                                   name: String) -> [Data] {
        [le16(Int(method)), le16(0), le16(0), le32(0), le32(compressed), le32(uncompressed),
         le16(name.utf8.count), le16(0)]
    }

    private static func localHeader(name: String, method: UInt16, compressed: Int,
                                    uncompressed: Int) -> Data {
        var data = Data()
        data.append(le32(0x0403_4B50))
        data.append(le16(20))
        data.append(le16(0))
        for part in sharedTail(method: method, compressed: compressed,
                               uncompressed: uncompressed, name: name) {
            data.append(part)
        }
        return data
    }

    private static func centralHeader(name: String, method: UInt16, compressed: Int,
                                      uncompressed: Int, offset: Int) -> Data {
        var data = Data()
        data.append(le32(0x0201_4B50))
        data.append(le16(20))
        data.append(le16(20))
        data.append(le16(0))
        for part in sharedTail(method: method, compressed: compressed,
                               uncompressed: uncompressed, name: name) {
            data.append(part)
        }
        data.append(le16(0))
        data.append(le16(0))
        data.append(le16(0))
        data.append(le32(0))
        data.append(le32(offset))
        return data
    }

    private static func endRecord(count: Int, centralOffset: Int, centralSize: Int) -> Data {
        var data = Data()
        data.append(le32(0x0605_4B50))
        data.append(le16(0))
        data.append(le16(0))
        data.append(le16(count))
        data.append(le16(count))
        data.append(le32(centralSize))
        data.append(le32(centralOffset))
        data.append(le16(0))
        return data
    }

    private static func le16(_ value: Int) -> Data {
        Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff)])
    }

    private static func le32(_ value: Int) -> Data {
        Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff),
              UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)])
    }
}

final class ZipArchiveTests: XCTestCase {
    func testStoredEntryComesBackByteForByte() {
        let payload = Data("PDF-DATEN \u{0}\u{1}\u{2}".utf8)
        let archive = TestZip.archive([(name: "word/document.xml", data: payload, deflate: false)])
        let zip = ZipArchive(data: archive)
        XCTAssertEqual(zip?.data(for: "word/document.xml"), payload)
    }

    func testDeflatedEntryIsInflatedToTheOriginal() {
        let payload = Data(String(repeating: "Hallo Word Dokument ", count: 40).utf8)
        let archive = TestZip.archive([(name: "word/document.xml", data: payload, deflate: true)])
        XCTAssertEqual(ZipArchive(data: archive)?.data(for: "word/document.xml"), payload)
    }

    func testSeveralEntriesKeepTheirOwnBytes() {
        let first = Data("erste".utf8)
        let second = Data("zweite".utf8)
        let archive = TestZip.archive([
            (name: "a.txt", data: first, deflate: true),
            (name: "b.txt", data: second, deflate: false),
        ])
        let zip = ZipArchive(data: archive)
        XCTAssertEqual(zip?.data(for: "a.txt"), first)
        XCTAssertEqual(zip?.data(for: "b.txt"), second)
        XCTAssertNil(zip?.data(for: "fehlt.txt"))
    }

    func testDataWithoutAnArchiveYieldsNothing() {
        XCTAssertNil(ZipArchive(data: Data("kein zip".utf8)))
    }
}

final class DocxTextTests: XCTestCase {
    private static let body = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:body>
    <w:p><w:r><w:t>Punkt 4.2: Budget 85.000 Euro &amp; mehr</w:t></w:r></w:p>
    <w:p><w:r><w:t>Zeile zwei</w:t></w:r><w:r><w:t> mit Fortsetzung</w:t></w:r></w:p>
    <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Zelle A</w:t></w:r></w:p></w:tc>
    <w:tc><w:p><w:r><w:t>Zelle B</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
    </w:body></w:document>
    """

    func testBodyTextParagraphsAndEntitiesAreRead() {
        let text = DocxText.text(fromDocumentXML: Data(Self.body.utf8))
        XCTAssertEqual(text?.contains("Punkt 4.2: Budget 85.000 Euro & mehr"), true)
        XCTAssertEqual(text?.contains("Zeile zwei mit Fortsetzung"), true)
        XCTAssertEqual(text?.contains("Zelle A\tZelle B"), true)
    }

    func testTabStopDefinitionsAreNoTabCharacters() {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        <w:p><w:r><w:t>Erster Absatz</w:t></w:r></w:p>
        <w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr></w:p>
        <w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr>
        <w:r><w:t>Name</w:t></w:r><w:r><w:tab/><w:t>Wert</w:t></w:r></w:p>
        </w:body></w:document>
        """
        XCTAssertEqual(DocxText.text(fromDocumentXML: Data(xml.utf8)), "Erster Absatz\nName\tWert")
    }

    func testDocumentPartInsideAZipIsFound() {
        let archive = TestZip.archive([
            (name: "[Content_Types].xml", data: Data("<Types/>".utf8), deflate: true),
            (name: DocxText.documentPart, data: Data(Self.body.utf8), deflate: true),
        ])
        let text = DocxText.text(from: archive)
        XCTAssertTrue(text?.contains("Budget 85.000 Euro") ?? false)
    }

    func testMissingOrBrokenPartsYieldNothing() {
        let withoutBody = TestZip.archive([
            (name: "[Content_Types].xml", data: Data("<Types/>".utf8), deflate: true),
        ])
        XCTAssertNil(DocxText.text(from: withoutBody))
        XCTAssertNil(DocxText.text(fromDocumentXML: Data("<w:document".utf8)))
        XCTAssertNil(DocxText.text(fromDocumentXML: Data("<w:document xmlns:w=\"x\"><w:body/></w:document>".utf8)))
    }
}

final class WordDocumentExtractionTests: XCTestCase {
    private func write(_ data: Data, as name: String) throws -> URL {
        let url = tempDocuments().appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testExtractionReadsTheWordBodyIntoTheDocumentKind() throws {
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body><w:p><w:r><w:t>Angebot: 85.000 Euro für den Ausbau</w:t></w:r></w:p></w:body>
        </w:document>
        """
        let archive = TestZip.archive([(name: DocxText.documentPart, data: Data(body.utf8), deflate: true)])
        let url = try write(archive, as: "angebot.docx")
        let extracted = DocumentExtractor.extract(url: url, kind: .docx, ocrLanguages: ["de-DE"])
        XCTAssertEqual(extracted.via, .docx)
        XCTAssertNil(extracted.pages)
        XCTAssertTrue(extracted.text.contains("85.000 Euro"))
        XCTAssertEqual(extracted.chars, extracted.text.count)
        XCTAssertFalse(extracted.truncated)
    }

    func testADocxWithoutReadableBodyReportsNoText() throws {
        let archive = TestZip.archive([(name: "word/styles.xml", data: Data("<styles/>".utf8), deflate: true)])
        let url = try write(archive, as: "leer.docx")
        let extracted = DocumentExtractor.extract(url: url, kind: .docx, ocrLanguages: ["de-DE"])
        XCTAssertEqual(extracted.via, .none)
        XCTAssertEqual(extracted.chars, 0)
    }

    func testLongWordBodyIsTrimmedToTheBudget() throws {
        let paragraph = "<w:p><w:r><w:t>" + String(repeating: "wort ", count: 40_000)
            + "</w:t></w:r></w:p>"
        let body = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + "<w:body>" + paragraph + "</w:body></w:document>"
        let archive = TestZip.archive([(name: DocxText.documentPart, data: Data(body.utf8), deflate: true)])
        let url = try write(archive, as: "lang.docx")
        let extracted = DocumentExtractor.extract(url: url, kind: .docx, ocrLanguages: ["de-DE"])
        XCTAssertTrue(extracted.truncated)
        XCTAssertEqual(extracted.chars, FilePolicy.maxTextChars)
    }
}
