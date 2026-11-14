@testable import GwenMobileFeatureCore
import PDFKit
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class DocumentExtractorCoverageTests: GwenTestCase {
    private func temporary(_ name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("extractor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testPlainTextCSVAndJSONAreExtracted() throws {
        let txt = try temporary("a.txt", data: Data("Zeile eins\nZeile zwei".utf8))
        let plain = DocumentExtractor.extract(url: txt, kind: .text, ocrLanguages: [])
        XCTAssertEqual(plain.via, .plain)
        XCTAssertEqual(plain.chars, "Zeile eins\nZeile zwei".count)
        let csv = try temporary("a.csv", data: Data("a,b\n1,2".utf8))
        XCTAssertEqual(DocumentExtractor.extract(url: csv, kind: .csv, ocrLanguages: []).via, .plain)
        let json = try temporary("a.json", data: Data(#"{"a":1}"#.utf8))
        XCTAssertEqual(DocumentExtractor.extract(url: json, kind: .json, ocrLanguages: []).via, .plain)
    }

    func testAWindowsCSVWithoutUTF8IsStillRead() throws {
        let csv = try temporary("umsatz.csv", data: Data([0x4D, 0xFC, 0x6C, 0x6C, 0x65, 0x72, 0x3B, 0x4B, 0xF6, 0x6C,
                                                          0x6E, 0x3B, 0x38, 0x30, 0x20, 0x80]))
        let extracted = DocumentExtractor.extract(url: csv, kind: .csv, ocrLanguages: [])
        XCTAssertEqual(extracted.text, "Müller;Köln;80 €")
        XCTAssertEqual(extracted.via, .plain)
    }

    func testTheTextEncodingIsRecognised() {
        XCTAssertEqual(PlainTextDecoding.text(of: Data("Grüße".utf8)), "Grüße")
        XCTAssertEqual(PlainTextDecoding.text(of: Data([0xEF, 0xBB, 0xBF, 0x41])), "A")
        XCTAssertEqual(PlainTextDecoding.text(of: Data([0xFF, 0xFE, 0x41, 0x00, 0xE4, 0x00])), "Aä")
        XCTAssertEqual(PlainTextDecoding.text(of: Data([0xFE, 0xFF, 0x00, 0x41, 0x00, 0xE4])), "Aä")
        XCTAssertEqual(PlainTextDecoding.text(of: Data([0x41, 0x00, 0xE4, 0x00])), "Aä")
        XCTAssertEqual(PlainTextDecoding.text(of: Data([0x00, 0x41, 0x00, 0xE4])), "Aä")
        XCTAssertEqual(PlainTextDecoding.text(of: Data([0x80, 0x41])), "€A")
        XCTAssertEqual(PlainTextDecoding.text(of: Data([0x81, 0xE4])), "\u{81}ä")
        XCTAssertEqual(PlainTextDecoding.text(of: Data()), "")
    }

    func testMissingAndBrokenFilesReportNothing() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("fehlt-\(UUID().uuidString).txt")
        let empty = DocumentExtractor.extract(url: missing, kind: .text, ocrLanguages: [])
        XCTAssertEqual(empty.chars, 0)
        XCTAssertEqual(empty.via, .none)
        let brokenPDF = try temporary("broken.pdf", data: Data([0, 1, 2, 3]))
        XCTAssertEqual(DocumentExtractor.extract(url: brokenPDF, kind: .pdf, ocrLanguages: []).via, .none)
        let brokenDocx = try temporary("broken.docx", data: Data([0, 1, 2]))
        XCTAssertEqual(DocumentExtractor.extract(url: brokenDocx, kind: .docx, ocrLanguages: []).via, .none)
    }

    func testRichTextIsRead() throws {
        let rtf = try temporary("a.rtf", data: Data("{\\rtf1\\ansi Hallo Welt}".utf8))
        let extracted = DocumentExtractor.extract(url: rtf, kind: .rtf, ocrLanguages: [])
        XCTAssertTrue(extracted.via == .richText || extracted.via == .none)
        let broken = try temporary("broken.rtf", data: Data([0, 1, 2]))
        XCTAssertEqual(DocumentExtractor.extract(url: broken, kind: .rtf, ocrLanguages: []).via, .none)
    }

    func testAPDFWithATextLayerIsExtracted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("extractor-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("seite.pdf")
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            let text = "Hallo PDF Welt" as NSString
            text.draw(at: CGPoint(x: 40, y: 40),
                      withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        try data.write(to: url)
        let extracted = DocumentExtractor.extract(url: url, kind: .pdf, ocrLanguages: [])
        XCTAssertGreaterThan(extracted.chars, 0)
        XCTAssertGreaterThanOrEqual(extracted.pages ?? 0, 1)
        XCTAssertTrue([.textLayer, .ocr].contains(extracted.via))
    }

    func testAPDFWithAMixedTextAndImagePageReadsBoth() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("extractor-pdf-mixed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("gemischt.pdf")
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let scanned = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(bounds)
            ("Gescannte Seite" as NSString).draw(at: CGPoint(x: 60, y: 80),
                                                 withAttributes: [.font: UIFont.systemFont(ofSize: 42)])
        }
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            ("Erste Seite mit Text" as NSString).draw(at: CGPoint(x: 40, y: 40),
                                                     withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            context.beginPage()
            scanned.draw(in: bounds)
        }
        try data.write(to: url)
        let extracted = DocumentExtractor.extract(url: url, kind: .pdf, ocrLanguages: ["de-DE", "en-US"])
        XCTAssertEqual(extracted.pages, 2)
        XCTAssertTrue(extracted.text.contains("Erste"))
        XCTAssertTrue(extracted.text.contains("Gescannte"), extracted.text)
        XCTAssertEqual(extracted.via, .ocr)
    }

    func testAPDFAboveThePageLimitIsMarkedTruncated() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("extractor-pdf-limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("lang.pdf")
        let totalPages = FilePolicy.maxPDFPages + 1
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for index in 0..<totalPages {
                context.beginPage()
                let text = "Seite \(index + 1) dieses Dokuments enthaelt Text." as NSString
                text.draw(at: CGPoint(x: 40, y: 40),
                          withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
        }
        try data.write(to: url)
        let extracted = DocumentExtractor.extract(url: url, kind: .pdf, ocrLanguages: [])
        XCTAssertEqual(extracted.pages, totalPages)
        XCTAssertTrue(extracted.truncated)
        XCTAssertFalse(extracted.text.isEmpty)
    }

func testTheOCRLimitMarksTheRemainingPagesAsTruncated() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("extractor-pdf-ocr-limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("scan.pdf")
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for _ in 0..<(FilePolicy.maxOCRPages + 1) {
                context.beginPage()
            }
        }
        try data.write(to: url)
        let extracted = DocumentExtractor.extract(url: url, kind: .pdf, ocrLanguages: ["en-US"])
        XCTAssertEqual(extracted.pages, FilePolicy.maxOCRPages + 1)
        XCTAssertTrue(extracted.truncated)
    }
}
