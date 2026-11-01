@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import UniformTypeIdentifiers
import GwenMobileKit
@testable import GwenMobileProbes

final class FileTextBlockTests: XCTestCase {
    func testExcerptKeepsShortTextUntouched() {
        let result = FileTextBlocks.excerpt("  Hallo Welt  ", limit: 100)
        XCTAssertEqual(result.text, "Hallo Welt")
        XCTAssertFalse(result.truncated)
    }

    func testExcerptCutsAndMarksLongText() {
        let long = String(repeating: "a", count: 500)
        let result = FileTextBlocks.excerpt(long, limit: 100)
        XCTAssertEqual(result.text.count, 100)
        XCTAssertTrue(result.truncated)
    }

    func testFileBlockCarriesNameViaAndEndMarker() {
        let block = FileTextBlocks.file(name: "Protokoll.pdf", pages: 6, text: "Inhalt",
                                        via: .textLayer, truncated: false)
        XCTAssertTrue(block.hasPrefix(FileTextBlocks.fileHead))
        XCTAssertTrue(block.contains("Protokoll.pdf"))
        XCTAssertTrue(block.contains("6 pages"))
        XCTAssertTrue(block.contains("text layer"))
        XCTAssertTrue(block.hasSuffix(FileTextBlocks.fileEnd))
    }

    func testTruncatedBlockSaysSo() {
        let block = FileTextBlocks.file(name: "a.txt", pages: nil, text: "x", via: .plain,
                                        truncated: true)
        XCTAssertTrue(block.contains("trimmed"))
    }

    func testPageMarkersAppearOnlyForMultiPageText() {
        let single = FileTextBlocks.pageMarked(["nur eine seite"])
        XCTAssertFalse(single.contains(FileTextBlocks.pageMarker))
        let multi = FileTextBlocks.pageMarked(["erste", "zweite"])
        XCTAssertTrue(multi.contains("--- page 1 ---"))
        XCTAssertTrue(multi.contains("--- page 2 ---"))
    }

    func testBudgetDropsOldestBlocksFirst() {
        let small = FileTextBlocks.file(name: "klein.txt", pages: nil, text: "x", via: .plain,
                                        truncated: false)
        let big = String(repeating: "y", count: 500)
        let joined = FileTextBlocks.joinedWithinBudget([small, big, small], budget: small.count * 2 + 4,
                                                       size: \.count, block: { $0 })
        XCTAssertEqual(joined.dropped, 1)
        XCTAssertEqual(joined.text.components(separatedBy: "\n\n").count, 2)
        XCTAssertEqual(joined.kept, [small, small])
    }

    func testBudgetCarriesTheKeptElementAlongWithItsBlock() {
        let small = "kurz"
        let big = String(repeating: "w", count: 300)
        let paired: [(name: String, block: String)] = [("alt.pdf", big), ("neu.pdf", small),
                                                       ("letztes.pdf", small)]
        let joined = FileTextBlocks.joinedWithinBudget(paired, budget: small.count * 2 + 2,
                                                       size: \.block.count, block: \.block)
        XCTAssertEqual(joined.dropped, 1)
        XCTAssertEqual(joined.kept.map(\.name), ["neu.pdf", "letztes.pdf"])
        XCTAssertTrue(joined.text.contains(small))
    }
}

final class FilePickerFilterTests: XCTestCase {
    private func pickerOffers(_ name: String) -> Bool {
        guard let type = UTType(filenameExtension: (name as NSString).pathExtension.lowercased()) else {
            return false
        }
        return FileKind.importTypes.contains { type.conforms(to: $0) }
    }

    func testThePickerOffersEveryKindTheReaderKnows() {
        for name in ["protokoll.pdf", "notiz.rtf", "brief.docx", "text.txt", "liest.md", "umsatz.csv",
                     "daten.json", "meldung.log", "clip.mp4", "clip.mov", "clip.webm"] {
            XCTAssertTrue(pickerOffers(name), "\(name) muss wählbar sein")
        }
    }

    func testThePickerRefusesWhatTheReaderCannotOpen() {
        for name in ["urlaub.heic", "spiel.app", "ohneendung"] {
            XCTAssertFalse(pickerOffers(name), "\(name) gehört nicht in die Liste")
        }
    }
}

final class AttachedFileTests: GwenTestCase {
    func testKindFromFilename() {
        XCTAssertEqual(FileKind(filename: "Protokoll.PDF"), .pdf)
        XCTAssertEqual(FileKind(filename: "scan.rtf"), .rtf)
        XCTAssertEqual(FileKind(filename: "Scan.RTF"), .rtf)
        XCTAssertEqual(FileKind(filename: "umsatz.csv"), .csv)
        XCTAssertEqual(FileKind(filename: "daten.json"), .json)
        XCTAssertEqual(FileKind(filename: "notiz.md"), .text)
        XCTAssertEqual(FileKind(filename: "clip.MP4"), .video)
        XCTAssertEqual(FileKind(filename: "clip.mov"), .video)
        XCTAssertNil(FileKind(filename: "bild.heic"))
    }

    func testTheVideoReaderReturnsNoTextWithoutFailing() throws {
        let url = tempDocuments().appendingPathComponent("clip.mp4")
        try Data("video".utf8).write(to: url)
        let extracted = DocumentExtractor.extract(url: url, kind: .video, ocrLanguages: [])
        XCTAssertEqual(extracted.text, "")
        XCTAssertEqual(extracted.chars, 0)
        XCTAssertEqual(extracted.via, .none)
        XCTAssertTrue(FileKind.videoImportTypes.contains { $0.conforms(to: .movie) })
    }

    func testVideoMetaNamesTheVideoAndItsSize() {
        let file = AttachedFile(file: "doc_v.mp4", name: "clip.mp4", kind: .video, bytes: 1_200_000)
        XCTAssertEqual(file.metaText, L.t("file_video") + " · " + StorageUsage.bytesText(1_200_000))
        XCTAssertTrue(file.isVideo)
    }

    func testMetaTextMentionsPagesBytesAndReading() {
        let file = AttachedFile(file: "doc_a.pdf", name: "a.pdf", kind: .pdf, bytes: 240_000,
                                pages: 6, chars: 11_840, via: .textLayer)
        let meta = file.metaText
        XCTAssertTrue(meta.contains("6 pages"))
        XCTAssertTrue(meta.contains("chars read"))
        XCTAssertTrue(meta.contains("KB"))
    }

    func testASinglePageIsCountedInTheSingular() {
        let file = AttachedFile(file: "doc_d.pdf", name: "d.pdf", kind: .pdf, bytes: 30_000,
                                pages: 1, chars: 112, via: .ocr)
        XCTAssertTrue(file.metaText.hasPrefix("1 page · "), file.metaText)
        L.apply(.de)
        XCTAssertTrue(file.metaText.hasPrefix("1 Seite · "), file.metaText)
    }

    func testTruncatedMetaTellsTheTrim() {
        let file = AttachedFile(file: "doc_b.txt", name: "b.txt", kind: .text, bytes: 90_000,
                                chars: 24_000, truncated: true, via: .plain)
        XCTAssertTrue(file.metaText.contains("trimmed to 24,000 chars"))
    }

    func testEmptyFileSaysNoText() {
        let file = AttachedFile(file: "doc_c.pdf", name: "c.pdf", kind: .pdf, bytes: 500,
                                pages: 2, chars: 0)
        XCTAssertTrue(file.metaText.contains("no text found"))
        XCTAssertFalse(file.hasText)
    }

    func testPagesDetailAndChipText() {
        let file = AttachedFile(file: "doc_d.pdf", name: "Protokoll.pdf", kind: .pdf, bytes: 10,
                                pages: 6, chars: 5, via: .textLayer)
        XCTAssertEqual(file.pagesDetail, "pages 1–6")
        let ref = FileRef(file)
        XCTAssertEqual(ref.chipText, "Protokoll.pdf · pages 1–6")
        XCTAssertEqual(ref.privacyKey, "file_local_pdfkit")
    }

    func testSinglePageDetailStaysQuiet() {
        let file = AttachedFile(file: "doc_e.pdf", name: "e.pdf", kind: .pdf, bytes: 10,
                                pages: 1, chars: 5)
        XCTAssertNil(file.pagesDetail)
    }
}

@MainActor
final class FilePersistenceTests: GwenTestCase {
    func testOldMessageJSONStillDecodesWithoutFileFields() throws {
        let json = Data("""
        {"id":"\(UUID().uuidString)","role":"user","text":"Frage","images":[],
         "date":\(Date().timeIntervalSince1970)}
        """.utf8)
        let message = try JSONDecoder().decode(ChatMessage.self, from: json)
        XCTAssertEqual(message.files, [])
        XCTAssertNil(message.fileRefs)
        XCTAssertNil(message.ocrFiles)
    }

    func testFilesAndRefsSurviveRoundTrip() throws {
        let message = ChatMessage(role: .user, text: "Frag die Datei",
                                  files: [AttachedFile(file: "doc_x.pdf", name: "x.pdf", kind: .pdf,
                                                       bytes: 99, pages: 3, chars: 42, via: .ocr)],
                                  ocrFiles: [OcrFile(file: "text_2026-09-16-1120_abcd1234.jpg.txt",
                                                     chars: 73)],
                                  fileRefs: [FileRef(name: "x.pdf", detail: "S. 1–3", via: .ocr)],
                                  fileRefsHeadingKey: "file_local_plain")
        let data = try JSONEncoder().encode(message)
        let back = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(back.files.count, 1)
        XCTAssertEqual(back.files[0].name, "x.pdf")
        XCTAssertEqual(back.files[0].via, .ocr)
        XCTAssertEqual(back.ocrFiles?.first?.chars, 73)
        XCTAssertEqual(back.ocrFiles?.first?.displayName,
                       "text_2026-09-16-1120_abcd1234.jpg.txt")
        XCTAssertEqual(back.fileRefs?.first?.chipText, "x.pdf · S. 1–3")
        XCTAssertEqual(back.fileRefsHeadingKey, "file_local_plain")
        XCTAssertEqual(back.documentFiles, ["doc_x.pdf"])
        XCTAssertTrue(back.files.contains(where: \.hasText))
    }

    func testEmptyFileEntriesAreDroppedOnDecode() throws {
        let json = Data("""
        {"id":"\(UUID().uuidString)","role":"user","text":"t","images":[],"files":[{"file":"","name":"leer"}],
         "date":\(Date().timeIntervalSince1970)}
        """.utf8)
        let message = try JSONDecoder().decode(ChatMessage.self, from: json)
        XCTAssertEqual(message.files, [])
    }
}

@MainActor
final class FileContextTests: GwenTestCase {
    private func pdf(_ name: String, file: String, chars: Int = 10) -> AttachedFile {
        AttachedFile(file: file, name: name, kind: .pdf, bytes: 1000, pages: 2, chars: chars,
                     via: .textLayer)
    }

    func testFileTextTravelsInsideTheSpeakerMessageOnly() {
        let history = [
            ChatMessage(role: .assistant, text: "Vorherige Antwort"),
            ChatMessage(role: .user, text: "Fass die Datei zusammen",
                        files: [pdf("Protokoll.pdf", file: "doc_p.pdf")]),
        ]
        let texts: [String: String] = ["doc_p.pdf": "Punkt eins: Budget 85.000 Euro"]
        let turn = ConversationMemory.turn(from: history, load: { _ in nil },
                                           fileText: { texts[$0] })
        let speaker = turn.messages.last!
        XCTAssertTrue(speaker.text.contains("## FILE Protokoll.pdf"))
        XCTAssertTrue(speaker.text.contains("Budget 85.000 Euro"))
        XCTAssertTrue(speaker.text.contains("## END OF FILE"))
        XCTAssertFalse(turn.messages.first!.text.contains("## FILE"))
    }

    func testImageOCRFilesNeverEnterTheModelContext() {
        let history = [ChatMessage(role: .user, text: "Was ist auf dem Foto?",
                                   images: [Attachment(file: "img_1.jpg"), Attachment(file: "img_2.jpg")],
                                   ocrFiles: [OcrFile(file: "text_a.jpg.txt", chars: 20),
                                              OcrFile(file: "text_b.jpg.txt", chars: 5)])]
        let turn = ConversationMemory.turn(from: history, load: { _ in nil },
                                           fileText: { _ in nil })
        XCTAssertFalse(turn.messages.last!.text.contains("## "))
    }

    func testMissingSidecarTextSkipsTheBlock() {
        let history = [ChatMessage(role: .user, text: "Frage",
                                   files: [pdf("feHLT.txt", file: "doc_missing.pdf")])]
        let turn = ConversationMemory.turn(from: history, load: { _ in nil },
                                           fileText: { _ in nil })
        XCTAssertFalse(turn.messages.last!.text.contains("## FILE"))
    }

    func testBudgetDropsTheOldestFileBlockFirst() {
        let big = String(repeating: "z", count: FilePolicy.maxContextChars)
        let history = [ChatMessage(role: .user, text: "Zwei Dateien",
                                   files: [pdf("alt.pdf", file: "doc_old.pdf", chars: big.count),
                                           pdf("neu.pdf", file: "doc_new.pdf", chars: 20)])]
        let texts: [String: String] = ["doc_old.pdf": big, "doc_new.pdf": "kurzer inhalt"]
        let turn = ConversationMemory.turn(from: history, load: { _ in nil },
                                           fileText: { texts[$0] })
        XCTAssertFalse(turn.messages.last!.text.contains("## FILE alt.pdf"))
        XCTAssertTrue(turn.messages.last!.text.contains("## FILE neu.pdf"))
    }

    func testTwoFilesAtTheTextLimitBothFitIntoTheContext() {
        let full = String(repeating: "t", count: FilePolicy.maxTextChars)
        let history = [ChatMessage(role: .user, text: "Zwei lange Dateien",
                                   files: [pdf("vertrag.pdf", file: "doc_first.pdf", chars: full.count),
                                           pdf("rechnung.pdf", file: "doc_second.pdf", chars: full.count)])]
        let turn = ConversationMemory.turn(from: history, load: { _ in nil }, fileText: { _ in full })
        let body = turn.messages.last?.text ?? ""
        XCTAssertTrue(body.contains("## FILE vertrag.pdf"))
        XCTAssertTrue(body.contains("## FILE rechnung.pdf"))
        XCTAssertFalse(body.contains("did not fit"))
        XCTAssertEqual(turn.carriedFileNames, ["vertrag.pdf", "rechnung.pdf"])
    }

    func testAnOversizedSingleBlockLeavesANoticeInsteadOfSilence() {
        let big = String(repeating: "q", count: FilePolicy.maxContextChars + 1)
        let history = [ChatMessage(role: .user, text: "Eine große Datei",
                                   files: [pdf("riesig.pdf", file: "doc_big.pdf", chars: big.count)])]
        let turn = ConversationMemory.turn(from: history, load: { _ in nil },
                                           fileText: { _ in big })
        let body = turn.messages.last!.text
        XCTAssertFalse(body.contains("## FILE riesig.pdf"))
        XCTAssertTrue(body.contains("did not fit"), body)
        XCTAssertTrue(turn.carriedFileNames.isEmpty)
    }

    func testAnswerChipsComeFromTheLatestUserFileOnly() {
        let history = [
            ChatMessage(role: .user, text: "alt", files: [pdf("alt.pdf", file: "doc_alt.pdf")]),
            ChatMessage(role: .assistant, text: "antwort"),
            ChatMessage(role: .user, text: "neu", files: [pdf("neu.pdf", file: "doc_neu.pdf")]),
        ]
        let refs = ChatView.fileRefs(from: history, carried: nil)
        XCTAssertEqual(refs.map(\.name), ["neu.pdf"])
    }

    func testToolRouterHearsAboutFilesOnlyWhenOneIsInPlay() {
        let withFile = ToolRouter.systemBlock(now: "2025-01-01",
                                              context: SendContext(attachedFile: true),
                                              transcript: "")
        XCTAssertTrue(withFile.contains("## FILE"))
        let withoutFile = ToolRouter.systemBlock(now: "2025-01-01", context: SendContext(),
                                                 transcript: "")
        XCTAssertFalse(withoutFile.contains("## FILE"))
    }

    func testSystemPromptCarriesTheFileProtocol() {
        XCTAssertTrue(SystemPrompt.chat().contains("## FILE"))
        XCTAssertTrue(SystemPrompt.fileProtocol.contains("Never invent file contents"))
    }
}

final class OcrTextStoreTests: GwenTestCase {
    func testNameFollowsImageDateAndPictureSuffix() {
        let suffixed = OcrTextStore.name(imageDate: Date(timeIntervalSince1970: 0), suffix: "abcd1234")
        XCTAssertTrue(suffixed.hasPrefix("text_1970"))
        XCTAssertTrue(suffixed.hasSuffix("_abcd1234.jpg.txt"))
        XCTAssertTrue(OcrTextStore.name(imageDate: Date()).hasSuffix(".jpg.txt"))
    }

    func testHandoverFileLandsInTemporarySpaceAndNotInDocuments() throws {
        let url = try XCTUnwrap(OcrTextStore.temporaryFile(named: "text_handover.jpg.txt",
                                                           text: "Erkannter Text"))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(url.path.hasPrefix(StoragePaths().documents.path))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Erkannter Text")
    }

    func testRemoveStoredTextClearsDocumentsAndTemporaryFolder() throws {
        let documents = tempDocuments().appendingPathComponent(OcrTextStore.folder, isDirectory: true)
        let temporary = tempDocuments().appendingPathComponent(OcrTextStore.folder, isDirectory: true)
        for folder in [documents, temporary] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "alt".write(to: folder.appendingPathComponent("text_alt.jpg.txt"),
                            atomically: true, encoding: .utf8)
        }
        OcrTextStore.removeStoredText(from: [documents, temporary])
        for folder in [documents, temporary] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "\(folder) ist geblieben")
        }
    }

    func testMetaTextReadsLikeBadge() {
        XCTAssertEqual(OcrFile(file: "text_x.jpg.txt", chars: 1234).metaText, "OCR · 1,234 chars")
    }
}

final class FileExtractionRuntimeTests: XCTestCase {
    func testPDFTextLayerIsExtractedWithPageMarkers() throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 420, height: 595))
        let data = renderer.pdfData { context in
            context.beginPage()
            NSAttributedString(string: "Punkt 4.2: Budget 85.000 Euro", attributes: [
                .font: UIFont.systemFont(ofSize: 24),
            ]).draw(in: CGRect(x: 30, y: 40, width: 360, height: 100))
            context.beginPage()
            NSAttributedString(string: "naechster Termin am 03.07.", attributes: [
                .font: UIFont.systemFont(ofSize: 24),
            ]).draw(in: CGRect(x: 30, y: 40, width: 360, height: 100))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("protokoll_\(UUID().uuidString.prefix(8)).pdf")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let extracted = DocumentExtractor.extract(url: url, kind: .pdf, ocrLanguages: ["de-DE", "en-US"])
        XCTAssertEqual(extracted.via, .textLayer)
        XCTAssertEqual(extracted.pages, 2)
        XCTAssertTrue(extracted.text.contains("Budget 85.000 Euro"))
        XCTAssertTrue(extracted.text.contains("--- page 2 ---"))
        XCTAssertFalse(extracted.truncated)
    }

    func testVisionOCRReadsRenderedScreenshotText() throws {
        let size = CGSize(width: 640, height: 220)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            NSAttributedString(string: "Aufgabe 3: Wie spaet ist es?", attributes: [
                .font: UIFont.boldSystemFont(ofSize: 44),
                .foregroundColor: UIColor.black,
            ]).draw(in: CGRect(x: 20, y: 60, width: size.width - 40, height: 120))
        }
        let text = try XCTUnwrap(TextRecognizing.recognize(image: image, languages: ["de-DE", "en-US"]))
        XCTAssertTrue(text.contains("Aufgabe 3"), "erkannt war: \(text)")
    }

    func testExcerptBudgetCapsLongPDFText() {
        let long = String(repeating: "wort ", count: 40_000)
        let excerpt = FileTextBlocks.excerpt(long, limit: FilePolicy.maxTextChars)
        XCTAssertTrue(excerpt.truncated)
        XCTAssertEqual(excerpt.text.count, FilePolicy.maxTextChars)
    }
}

@MainActor
final class DocumentStoreTests: XCTestCase {
    private func makeStore() -> (DocumentStore, StoragePaths) {
        let paths = StoragePaths(documents: tempDocuments())
        let store = DocumentStore(paths: paths)
        store.prepareDirectories()
        return (store, paths)
    }

    private func writeTemp(_ name: String, _ data: Data) throws -> URL {
        let url = tempDocuments().appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testStoreCopyKeepsExtensionAndBytes() throws {
        let (store, _) = makeStore()
        let payload = Data("PDF-DATEN".utf8)
        let source = try writeTemp("Protokoll.pdf", payload)
        let stored = try XCTUnwrap(store.store(url: source))
        XCTAssertTrue(stored.file.hasPrefix("doc_"))
        XCTAssertTrue(stored.file.hasSuffix(".pdf"))
        XCTAssertEqual(stored.bytes, payload.count)
        XCTAssertNotNil(store.storedURL(for: stored.file))
    }

    func testStoreDataWritesAContentAddressedDocument() throws {
        let (store, _) = makeStore()
        let payload = Data("MP4-DATEN".utf8)
        let stored = try XCTUnwrap(store.store(data: payload, fileExtension: "mp4"))
        XCTAssertTrue(stored.file.hasPrefix("doc_"))
        XCTAssertTrue(stored.file.hasSuffix(".mp4"))
        XCTAssertEqual(stored.bytes, payload.count)
        XCTAssertEqual(store.data(named: stored.file), payload)
    }

    func testWritingVideoDataReportsAFailedSupportDirectory() throws {
        let root = tempDocuments()
        let supportFile = root.appendingPathComponent("support-is-a-file")
        try Data("kein ordner".utf8).write(to: supportFile)
        let store = DocumentStore(paths: StoragePaths(documents: root, support: supportFile))
        XCTAssertNil(store.store(data: Data("video".utf8), fileExtension: "mp4"))
    }

    func testTextSidecarRoundTrip() throws {
        let (store, _) = makeStore()
        let source = try writeTemp("notiz.txt", Data("x".utf8))
        let stored = try XCTUnwrap(store.store(url: source))
        store.writeText("extrahierter text", for: stored.file)
        XCTAssertEqual(store.text(named: stored.file), "extrahierter text")
    }

    func testDiscardingTrashedEntriesRemovesFileAndSidecarOnlyForItself() throws {
        let (store, paths) = makeStore()
        let own = try XCTUnwrap(store.store(url: try writeTemp("eigene.txt", Data("ins ownere".utf8)))?.file)
        let other = try XCTUnwrap(store.store(url: try writeTemp("andere.txt", Data("ins andere".utf8)))?.file)
        store.writeText("text eigene", for: own)
        store.writeText("text andere", for: other)
        let movedOwn = store.moveFilesToTrash([own])
        let movedOther = store.moveFilesToTrash([other])
        XCTAssertEqual(movedOwn.count, 1)

        store.discardTrashed(movedOwn)

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.trashItem(movedOwn[0].trashed).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.trashItem("txt_\(movedOwn[0].trashed)").path))
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: paths.trash.path))
        XCTAssertEqual(left, Set([movedOther[0].trashed, "txt_\(movedOther[0].trashed)"]))
    }

    func testTrashAndRestoreBringBackOriginalAndSidecar() throws {
        let (store, _) = makeStore()
        let source = try writeTemp("a.txt", Data("inhalt".utf8))
        let stored = try XCTUnwrap(store.store(url: source))
        store.writeText("seite eins", for: stored.file)
        let trashed = store.moveFilesToTrash([stored.file])
        XCTAssertEqual(trashed.count, 1)
        XCTAssertNil(store.storedURL(for: stored.file))
        XCTAssertNil(store.text(named: stored.file))
        store.restoreFromTrash(trashed)
        XCTAssertNotNil(store.storedURL(for: stored.file))
        XCTAssertEqual(store.text(named: stored.file), "seite eins")
    }

    func testInventoryIgnoresSidecars() throws {
        let (store, _) = makeStore()
        let source = try writeTemp("b.txt", Data("y".utf8))
        let stored = try XCTUnwrap(store.store(url: source))
        store.writeText("text", for: stored.file)
        XCTAssertEqual(store.fileNames(), [stored.file])
        XCTAssertEqual(store.sizesByName()[stored.file], 1)
    }

    func testMoveFilesToTrashSkipsUnknownNames() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.moveFilesToTrash(["doc_ghost.pdf"]).count, 0)
    }
}

@MainActor
final class FileHistoryIntegrationTests: GwenTestCase {
    private func makeStage() -> (ChatStore, MediaStore, DocumentStore) {
        let paths = StoragePaths(documents: tempDocuments())
        let media = MediaStore(paths: paths)
        let store = ChatStore(media: media, paths: paths)
        return (store, media, store.documents)
    }

    private func attachFile(to store: ChatStore, name: String, text: String) throws -> String {
        let dir = tempDocuments()
        let source = dir.appendingPathComponent(name)
        try Data("roh".utf8).write(to: source)
        let stored = try XCTUnwrap(store.documents.store(url: source))
        store.documents.writeText(text, for: stored.file)
        let attached = AttachedFile(file: stored.file, name: name, kind: .pdf, bytes: 3,
                                    pages: 2, chars: text.count, via: .textLayer)
        store.appendMessage(ChatMessage(role: .user, text: "Frag die Datei", files: [attached]),
                            to: try XCTUnwrap(store.current?.id))
        return stored.file
    }

    func testDeletingAMessageTrashesItsFileAndUndoRestoresEverything() throws {
        let (store, _, documents) = makeStage()
        let file = try attachFile(to: store, name: "Protokoll.pdf", text: "Punkt 4.2 Budget")
        let messageID = try XCTUnwrap(store.current?.messages.last?.id)

        store.cleaner.deleteMessage(messageID, in: try XCTUnwrap(store.current?.id))
        XCTAssertNil(documents.storedURL(for: file))
        XCTAssertNil(documents.text(named: file))

        store.cleaner.undoLast()
        XCTAssertNotNil(documents.storedURL(for: file))
        XCTAssertEqual(documents.text(named: file), "Punkt 4.2 Budget")
    }

    func testUsageCountsDocumentBytes() async throws {
        let (store, _, documents) = makeStage()
        _ = try attachFile(to: store, name: "umsatz.csv", text: "Jahr;Umsatz\n2021;10")
        let conversationID = try XCTUnwrap(store.current?.id)
        let usage = StorageMeasurement.usage(conversations: store.conversations, images: store.media,
                                             documents: documents)
        XCTAssertEqual(usage.documentFiles, 1)
        XCTAssertGreaterThan(usage.documentBytes, 0)
        XCTAssertGreaterThan(usage.bytesByConversation[conversationID] ?? 0, 0)
    }

    func testDeleteAllBodyMentionsFilesOnlyWhenThereAreSome() throws {
        _ = makeStage()
        var usage = StorageUsage()
        usage.conversations = 1
        usage.messages = 1
        XCTAssertTrue(usage.deleteAllBody.contains("0 images"))
        usage.documentFiles = 2
        usage.documentBytes = 4096
        XCTAssertTrue(usage.deleteAllBody.contains("files"))
    }
}

final class RichTextFileTests: GwenTestCase {
    private func writeTemp(_ data: Data, _ name: String) throws -> URL {
        let url = tempDocuments().appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    private func wrapped(_ hex: String, every step: Int) -> String {
        stride(from: 0, to: hex.count, by: step).map { String(hex.dropFirst($0).prefix(step)) }
            .joined(separator: "\r\n")
    }

    private static let shortReceiptText = "ZWEI KAFFEE 14,80 EURO TISCH SIEBEN"

    private func receiptImage() -> UIImage {
        ReceiptCard.receiptCard(fontSize: 60, text: Self.shortReceiptText,
                                  canvas: CGSize(width: 900, height: 320),
                                  rect: CGRect(x: 20, y: 110, width: 860, height: 120))
    }

    private func generatedRTF(_ text: String) throws -> Data {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 22),
            .foregroundColor: UIColor.black,
        ])
        return try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                   documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    private func pictureGroup(_ image: UIImage, keyword: String = "pngblip",
                              wrapEvery: Int = 0) throws -> String {
        let blob = keyword == "pngblip" ? try XCTUnwrap(image.pngData()) : try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let body = wrapEvery > 0 ? wrapped(hex(blob), every: wrapEvery) : hex(blob)
        return "{\\pict\\" + keyword + "\\picw500\\pich350\\picwgoal360\\pichgoal252 " + body + "}"
    }

    private func handWrittenRTF(_ body: String) -> Data {
        let source = "{\\rtf1\\ansi\\deff0 {\\fonttbl{\\f0 Helvetica;}}\\pard\\fs44 " + body + "\\par}"
        return Data(source.utf8)
    }

    private func assertRTFOcr(_ url: URL) {
        let extracted = DocumentExtractor.extract(url: url, kind: .rtf, ocrLanguages: ["en-US"])
        XCTAssertEqual(extracted.via, .ocr)
        XCTAssertEqual(extracted.pages, 1)
        XCTAssertTrue(extracted.text.uppercased().contains("KAFFEE"), "erkannt war: \(extracted.text)")
        XCTAssertTrue(extracted.text.contains("14,80"), "erkannt war: \(extracted.text)")
    }

    func testGeneratedRTFYieldsItsPlainTextThroughTheRichTextLayer() throws {
        let text = "Punkt 4.2: Für den Ausbau des Lagers sind 85.000 Euro vorgesehen. "
            + String(repeating: "Zusatztextwort ", count: 40)
        let url = try writeTemp(try generatedRTF(text), "notiz.rtf")
        defer { try? FileManager.default.removeItem(at: url) }

        let extracted = DocumentExtractor.extract(url: url, kind: .rtf, ocrLanguages: ["de-DE", "en-US"])
        XCTAssertEqual(extracted.via, .richText)
        XCTAssertNil(extracted.pages)
        XCTAssertTrue(extracted.text.contains("85.000 Euro"))
        XCTAssertFalse(extracted.text.contains("rtf1"))
        XCTAssertFalse(extracted.truncated)
        XCTAssertEqual(extracted.chars, extracted.text.count)
    }

    func testSmokeScannedPictureInsideRTFIsReadByOCR() throws {
        let url = try writeTemp(handWrittenRTF(try pictureGroup(receiptImage())), "scan.rtf")
        defer { try? FileManager.default.removeItem(at: url) }

        assertRTFOcr(url)
    }

    func testSmokeJPEGPictureInsideRTFIsReadByOCR() throws {
        let group = try pictureGroup(receiptImage(), keyword: "jpegblip", wrapEvery: 60)
        let url = try writeTemp(handWrittenRTF(group), "foto.rtf")
        defer { try? FileManager.default.removeItem(at: url) }

        assertRTFOcr(url)
    }

    func testRTFWithTextAndScannedPictureKeepsBothParts() throws {
        let group = try pictureGroup(receiptImage())
        let body = "Punkt 4.2: Budget 85.000 Euro im Lager.\\par " + group
        let url = try writeTemp(handWrittenRTF(body), "mix.rtf")
        defer { try? FileManager.default.removeItem(at: url) }

        let extracted = DocumentExtractor.extract(url: url, kind: .rtf, ocrLanguages: ["en-US"])
        XCTAssertEqual(extracted.via, .ocr)
        XCTAssertTrue(extracted.text.contains("85.000 Euro"), "text lost: \(extracted.text)")
        XCTAssertTrue(extracted.text.uppercased().contains("KAFFEE"), "ocr lost: \(extracted.text)")
    }

    func testExtractionOfRTFRunsOnABackgroundThread() async throws {
        let text = String(repeating: "Rechenzeitwort ", count: 500)
        let url = try writeTemp(try generatedRTF(text), "last.rtf")
        defer { try? FileManager.default.removeItem(at: url) }

        let extracted = await Offload.orNil {
            DocumentExtractor.extract(url: url, kind: .rtf, ocrLanguages: ["en-US"])
        }
        XCTAssertEqual(extracted?.via, .richText)
        XCTAssertTrue((extracted?.text ?? "").hasPrefix("Rechenzeitwort"))
    }

    func testRTFWithoutAnyTextOrPictureReportsNoText() throws {
        let url = try writeTemp(handWrittenRTF(""), "leer.rtf")
        defer { try? FileManager.default.removeItem(at: url) }

        let extracted = DocumentExtractor.extract(url: url, kind: .rtf, ocrLanguages: ["en-US"])
        XCTAssertEqual(extracted.via, .none)
        XCTAssertEqual(extracted.chars, 0)
    }

    func testLongRTFTextIsTrimmedToTheBudget() throws {
        let url = try writeTemp(try generatedRTF(String(repeating: "wort ", count: 40_000)), "lang.rtf")
        defer { try? FileManager.default.removeItem(at: url) }

        let extracted = DocumentExtractor.extract(url: url, kind: .rtf, ocrLanguages: ["en-US"])
        XCTAssertTrue(extracted.truncated)
        XCTAssertEqual(extracted.chars, FilePolicy.maxTextChars)
    }

    func testRichTextPictureGroupsFindPNGAndJPEGButIgnoreShortAndForeignGroups() throws {
        let png = try pictureGroup(receiptImage())
        let jpg = try pictureGroup(receiptImage(), keyword: "jpegblip")
        let withBoth = handWrittenRTF(png + "\\par " + jpg)
        XCTAssertEqual(RichTextFile.pictures(in: withBoth).count, 2)
        XCTAssertTrue(RichTextFile.pictures(in: handWrittenRTF("{\\pict\\pngblip 89504E47}")).isEmpty)
        XCTAssertTrue(RichTextFile.pictures(in: Data("kein bild hier".utf8)).isEmpty)
    }

    func testBinaryPayloadInsideRTFIsReadAsPicture() throws {
        let picture = try XCTUnwrap(receiptImage().pngData())
        let opening = "{\\rtf1\\ansi\\deff0 {\\fonttbl{\\f0 Helvetica;}}\\pard\\fs44 "
            + "{\\pict\\pngblip\\picw500\\pich350\\bin \(picture.count) "
        let head = Data(opening.utf8)
        let tail = Data("}\\par}".utf8)
        let found = RichTextFile.pictures(in: head + picture + tail)
        XCTAssertEqual(found.count, 1, "\\bin trägt dasselbe Bild wie die Hex-Variante")
        XCTAssertEqual(found.first, picture)
    }

    func testBinaryPayloadShorterThanPromisedYieldsNothing() throws {
        let picture = try XCTUnwrap(receiptImage().pngData())
        let head = Data("{\\pict\\pngblip\\bin \(picture.count + 500) ".utf8)
        XCTAssertTrue(RichTextFile.pictures(in: head + picture + Data("}".utf8)).isEmpty)
    }

    func testAnOverlongBinaryLengthIsRejectedInsteadOfOverflowing() {
        let overflow = Data("{\\pict\\pngblip\\bin 99999999999999999999999999999999 89504E47}".utf8)
        XCTAssertTrue(RichTextFile.pictures(in: overflow).isEmpty)
        let maximum = Data("{\\pict\\pngblip\\bin 9223372036854775807 89504E47}".utf8)
        XCTAssertTrue(RichTextFile.pictures(in: maximum).isEmpty)
    }

    func testRichTextCardBadgeAndPill() {
        XCTAssertEqual(FileGlyph.label(for: .rtf), "RTF")
        let file = AttachedFile(file: "doc_r.rtf", name: "Notiz.rtf", kind: .rtf, bytes: 4_200,
                                chars: 512, via: .richText)
        XCTAssertTrue(file.metaText.contains("512 chars read"))
        XCTAssertEqual(FileRef(file).privacyKey, "file_local_rich")
        XCTAssertEqual(FileRef(file).chipText, "Notiz.rtf")
    }

    func testRichTextFileBlockTellsWhereTheTextCameFrom() {
        let block = FileTextBlocks.file(name: "Notiz.rtf", pages: nil, text: "Inhalt",
                                        via: .richText, truncated: false)
        XCTAssertTrue(block.contains("Notiz.rtf"))
        XCTAssertTrue(block.contains("rich text read on this device"))
        XCTAssertTrue(block.hasSuffix(FileTextBlocks.fileEnd))
    }

    func testRTFKindSurvivesTheMessageRoundTrip() throws {
        let message = ChatMessage(role: .user, text: "Was steht in der Notiz?",
                                  files: [AttachedFile(file: "doc_r.rtf", name: "Notiz.rtf", kind: .rtf,
                                                       bytes: 4_200, chars: 512, via: .richText)])
        let back = try JSONDecoder().decode(ChatMessage.self,
                                           from: try JSONEncoder().encode(message))
        XCTAssertEqual(back.files.first?.kind, .rtf)
        XCTAssertEqual(back.files.first?.via, .richText)
    }
}
