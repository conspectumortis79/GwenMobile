@testable import GwenMobileAdapters
@testable import GwenMobileFeatureCore
import XCTest
import UniformTypeIdentifiers
import GwenMobileKit

final class DropPolicyTests: XCTestCase {
    func testTheRequestedPictureFormatsBecomePictures() {
        for name in ["urlaub.jpg", "urlaub.jpeg", "bild.PNG", "scan.tiff", "scan.TIF"] {
            XCTAssertEqual(DropPolicy.item(forFileNamed: name), .picture, name)
        }
    }

    func testTheRequestedDocumentsBecomeDocuments() {
        XCTAssertEqual(DropPolicy.item(forFileNamed: "Protokoll.PDF"), .document(.pdf))
        XCTAssertEqual(DropPolicy.item(forFileNamed: "Notiz.rtf"), .document(.rtf))
        XCTAssertEqual(DropPolicy.item(forFileNamed: "brief.docx"), .document(.docx))
        XCTAssertEqual(DropPolicy.item(forFileNamed: "text.txt"), .document(.text))
        XCTAssertEqual(DropPolicy.item(forFileNamed: "umsatz.csv"), .document(.csv))
        XCTAssertEqual(DropPolicy.item(forFileNamed: "daten.json"), .document(.json))
        XCTAssertEqual(DropPolicy.item(forFileNamed: "clip.mov"), .document(.video))
        XCTAssertEqual(DropPolicy.item(forFileNamed: "clip.MP4"), .document(.video))
    }

    func testWhatTheAppCannotReadIsRefused() {
        for name in ["urlaub.heic", "spiel.app", "ohneendung", "archiv.zip"] {
            XCTAssertNil(DropPolicy.item(forFileNamed: name), name)
        }
    }
}

final class DropPromptTests: GwenTestCase {
    func testOneFileAsksForOneFileAnalysis() {
        XCTAssertEqual(DropPrompt.text(pictures: 0, files: 1), L.t("drop_analyze_file"))
    }

    func testSeveralFilesAskForTheFilesAnalysis() {
        XCTAssertEqual(DropPrompt.text(pictures: 0, files: 3), L.t("drop_analyze_files"))
    }

    func testOnePictureAsksForThePictureAnalysis() {
        XCTAssertEqual(DropPrompt.text(pictures: 1, files: 0), L.t("drop_analyze_picture"))
    }

    func testSeveralPicturesAskForThePicturesAnalysis() {
        XCTAssertEqual(DropPrompt.text(pictures: 2, files: 0), L.t("drop_analyze_pictures"))
    }

    func testMixedContentAsksForBothAnalyses() {
        XCTAssertEqual(DropPrompt.text(pictures: 1, files: 2), L.t("drop_analyze_mixed"))
        XCTAssertEqual(DropPrompt.text(pictures: 2, files: 1), L.t("drop_analyze_mixed"))
    }

    func testEveryDropPromptExistsInEveryLanguage() {
        for key in ["drop_hint", "drop_busy", "drop_no_text", "drop_analyze_file", "drop_analyze_files",
                    "drop_analyze_picture", "drop_analyze_pictures", "drop_analyze_mixed",
                    "file_local_docx"] {
            for language in AppLanguage.allCases {
                XCTAssertFalse((L.strings[key]?[language] ?? "").isEmpty, "\(key) [\(language.rawValue)]")
            }
        }
    }
}

final class WordFileKindTests: GwenTestCase {
    func testKindFromFilename() {
        XCTAssertEqual(FileKind(filename: "Brief.DOCX"), .docx)
        XCTAssertEqual(FileKind(filename: "Anhang.docx"), .docx)
        XCTAssertNil(FileKind(filename: "tabelle.xlsx"))
    }

    func testThePickerOffersDocxToTheReader() {
        XCTAssertTrue(FileKind.importTypes.contains { $0.identifier == UTType(filenameExtension: "docx")?.identifier })
    }

    func testBadgeAndPrivacyKeyNameTheWordReader() {
        XCTAssertEqual(FileGlyph.label(for: .docx), "DOCX")
        let file = AttachedFile(file: "doc_w.docx", name: "brief.docx", kind: .docx, bytes: 9_000,
                                chars: 1_200, via: .docx)
        XCTAssertEqual(FileRef(file).privacyKey, "file_local_docx")
        XCTAssertTrue(file.metaText.contains("1,200 chars read"))
    }

    func testFileBlockTellsWhereTheWordTextCameFrom() {
        let block = FileTextBlocks.file(name: "brief.docx", pages: nil, text: "Inhalt",
                                        via: .docx, truncated: false)
        XCTAssertTrue(block.contains("brief.docx"))
        XCTAssertTrue(block.contains("DOCX"))
        XCTAssertTrue(block.hasSuffix(FileTextBlocks.fileEnd))
    }

    func testWordKindAndReaderSurviveTheMessageRoundTrip() throws {
        let message = ChatMessage(role: .user, text: "Fass den Brief zusammen",
                                  files: [AttachedFile(file: "doc_w.docx", name: "brief.docx",
                                                       kind: .docx, bytes: 9_000, chars: 1_200,
                                                       via: .docx)])
        let back = try JSONDecoder().decode(ChatMessage.self,
                                           from: try JSONEncoder().encode(message))
        XCTAssertEqual(back.files.first?.kind, .docx)
        XCTAssertEqual(back.files.first?.via, .docx)
    }
}
