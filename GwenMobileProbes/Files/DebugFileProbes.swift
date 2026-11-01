@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum DebugFileProbe {
    static func run(_ name: String, view: ChatView) async -> Bool {
        switch name {
        case "pdftest": await pdfTest(view)
        case "pdftest.scan": await scanTest(view)
        case "rtftest": await rtfTest(view)
        case "rtftest.scan": await rtfScanTest(view)
        case "ocrtest": await ocrTest(view)
        case "droptest": await dropScenario(view, files: ["brief.docx"], report: "drop_docx.txt")
        case "droppic": await dropScenario(view, files: ["foto.jpg"], report: "drop_jpg.txt")
        case "dropmix": await dropScenario(view, files: ["protokoll.pdf", "foto.jpg"], report: "drop_mixed.txt")
        default: return false
        }
        return true
    }

    private static func pdf(_ text: String, pages: Int) -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 420, height: 595))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("protokoll_\(UUID().uuidString.prefix(8)).pdf")
        let data = renderer.pdfData { context in
            for page in 1...pages {
                context.beginPage()
                NSAttributedString(string: text, attributes: [
                    .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                ]).draw(in: CGRect(x: 30, y: 40 + page * 12, width: 360, height: 480))
            }
        }
        try? data.write(to: url)
        return url
    }

    private static func receiptImage() -> UIImage { ReceiptCard.receiptCard(fontSize: 46) }

    private static func scannedPDF() -> URL {
        let shot = receiptImage()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 420, height: 595))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan_\(UUID().uuidString.prefix(8)).pdf")
        let data = renderer.pdfData { context in
            for _ in 1...2 {
                context.beginPage()
                shot.draw(in: CGRect(x: 10, y: 40, width: 400, height: 280))
            }
        }
        try? data.write(to: url)
        return url
    }

    static func richText(_ text: String) -> URL {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 22),
            .foregroundColor: UIColor.black,
        ])
        let data = (try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                         documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notiz_\(UUID().uuidString.prefix(8)).rtf")
        try? data.write(to: url)
        return url
    }

    private static func hexDump(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    private static func scannedRTF() -> URL {
        let hex = hexDump(receiptImage().pngData() ?? Data())
        let source = "{\\rtf1\\ansi\\deff0 {\\fonttbl{\\f0 Helvetica;}}\\pard\\par "
            + "{\\pict\\pngblip\\picw500\\pich350\\picwgoal360\\pichgoal252 " + hex + "}\\par}"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan_\(UUID().uuidString.prefix(8)).rtf")
        try? source.data(using: .isoLatin1)?.write(to: url)
        return url
    }

    private static func pdfTest(_ view: ChatView) async {
        let report = SweepReport(file: "pdf_test.txt")
        let store = view.store
        let documents = store.documents
        let budgetText = "Punkt 4.2: Für den Ausbau des Lagers sind 85.000 Euro vorgesehen."
        let url = pdf(budgetText, pages: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        let started = ContinuousClock.now
        let extracted = await Offload.orNil {
            DocumentExtractor.extract(url: url, kind: .pdf, ocrLanguages: TextRecognizing.languages)
        }
        report.add("EXTRAKTION", "ms=\(msOf(started.duration(to: .now))) "
                   + "via=\(extracted?.via.rawValue ?? "keine") seiten=\(extracted?.pages.map(String.init) ?? "-") "
                   + "zeichen=\(extracted?.chars ?? -1) marker2=\(extracted?.text.contains("--- page 2 ---") == true) "
                   + "budget=\(extracted?.text.contains("85.000") == true)")

        let stored = documents.store(url: url)
        if let stored {
            documents.writeText(extracted?.text ?? "", for: stored.file)
            report.add("ABLAGE", "name=\(stored.file) bytes=\(stored.bytes) "
                       + "text_wieder=\(documents.text(named: stored.file) == extracted?.text) "
                       + "beleg_da=\(documents.storedURL(for: stored.file) != nil)")
        }
        let meta = AttachedFile(file: stored?.file ?? "", name: "Protokoll.pdf", kind: .pdf,
                                bytes: stored?.bytes ?? 0, pages: 2,
                                chars: extracted?.chars ?? 0, via: .textLayer)
        report.add("KARTE", "zeilen=\(TextLine.oneLine(meta.metaText, limit: 160)) "
                   + "detail=\(meta.pagesDetail ?? "-") pill=\(FileRef(meta).privacyKey ?? "-")")

        let trimmed = FileTextBlocks.excerpt(String(repeating: "wort ", count: 30_000),
                                             limit: FilePolicy.maxTextChars)
        report.add("BUDGET", "zeichen=\(trimmed.text.count) gekuerzt=\(trimmed.truncated)")

        guard store.current != nil else {
            report.add("KETTE", "keine unterhaltung")
            return
        }
        store.newConversation()
        guard let probeConv = store.current?.id else {
            report.add("KETTE", "keine frische unterhaltung")
            return
        }
        let pending = PendingFile(name: "Protokoll.pdf", kind: .pdf, file: stored?.file ?? "",
                                  bytes: stored?.bytes ?? 0, pages: 2,
                                  chars: extracted?.chars ?? 0, via: .textLayer, reading: false)
        view.pendingFiles = [pending]
        view.input = "Was steht im Protokoll genau zum Lager-Budget? Ein Satz."
        let turn = await sentTurn(view)
        let question = turn.question
        let answer = turn.answer
        report.add("KETTE", "ms=\(turn.ms) anhang_dateien=\(question?.files.count ?? -1) "
                   + "antwort_zeichen=\(answer?.text.count ?? -1) "
                   + "chips=\(answer?.fileRefs?.count ?? -1) chip=\(answer?.fileRefs?.first?.chipText ?? "-") "
                   + "budget_in_antwort=\(answer?.text.contains("85.000") == true) "
                   + "text=\(TextLine.oneLine(answer?.text ?? "", limit: 160))")
        report.add("KETTE_SPEICHER", "persistiert=\(question?.files.first?.name ?? "-") "
                   + "seiten=\(question?.files.first?.pages.map(String.init) ?? "-") "
                   + "via=\(question?.files.first?.via.rawValue ?? "-")")

        let before = documents.storedURL(for: pending.file) != nil
        store.cleaner.deleteConversation(probeConv)
        report.add("LÖSCHUNG", "vorher_da=\(before) datei_weg=\(documents.storedURL(for: pending.file) == nil) "
                   + "text_weg=\(documents.text(named: pending.file) == nil)")
        store.cleaner.undoLast()
        report.add("UNDO", "datei_wieder=\(documents.storedURL(for: pending.file) != nil) "
                   + "text_wieder=\(documents.text(named: pending.file) != nil)")
        store.cleaner.deleteConversation(probeConv)
        store.cleaner.discardPendingDeletion()
        report.add("ENDGÜLTIG", "datei_weg=\(documents.storedURL(for: pending.file) == nil) "
                   + "trash_leer=\(((try? FileManager.default.contentsOfDirectory(atPath: documents.paths.trash.path)) ?? []).isEmpty)")
        flowLog.info("PDFTEST fertig")
    }

    private static func scanTest(_: ChatView) async {
        let report = SweepReport(file: "pdf_scan.txt")
        let url = scannedPDF()
        defer { try? FileManager.default.removeItem(at: url) }
        let found = await scanExtraction(from: url, kind: .pdf)
        report.add("SCAN_OCR", scanFindings(found)
                   + " seiten=\(found.extracted?.pages.map(String.init) ?? "-")")
        flowLog.info("SCANTEST fertig")
    }

    private static func scanExtraction(from url: URL, kind: FileKind)
        async -> (ms: Int, extracted: ExtractedText?) {
        let started = ContinuousClock.now
        let extracted = await Offload.orNil {
            DocumentExtractor.extract(url: url, kind: kind, ocrLanguages: ["de-DE", "en-US"])
        }
        return (msOf(started.duration(to: .now)), extracted)
    }

    @MainActor private static func sentTurn(_ view: ChatView) async
        -> (ms: Int, messages: [ChatMessage], question: ChatMessage?, answer: ChatMessage?) {
        let chain = ContinuousClock.now
        await view.send()
        let messages = view.store.current?.messages ?? []
        return (msOf(chain.duration(to: .now)), messages,
                messages.last(where: { $0.role == .user }),
                messages.last(where: { $0.role == .assistant }))
    }

    private static func scanFindings(_ found: (ms: Int, extracted: ExtractedText?)) -> String {
        let extracted = found.extracted
        return "ms=\(found.ms) via=\(extracted?.via.rawValue ?? "keine") "
            + "zeichen=\(extracted?.chars ?? -1) "
            + "kaffee=\(extracted?.text.uppercased().contains("KAFFEE") == true) "
            + "betrag=\(extracted?.text.contains("14,80") == true) "
            + "text=\(TextLine.oneLine(extracted?.text ?? "", limit: 160))"
    }

    private static func rtfTest(_ view: ChatView) async {
        let report = SweepReport(file: "rtf_test.txt")
        let store = view.store
        let documents = store.documents
        let budgetText = "Punkt 4.2: Für den Ausbau des Lagers sind 85.000 Euro vorgesehen. "
            + "Termin: nächste Woche, 03.07."
        let url = richText(budgetText)
        defer { try? FileManager.default.removeItem(at: url) }

        let started = ContinuousClock.now
        let extracted = await Offload.orNil {
            DocumentExtractor.extract(url: url, kind: .rtf, ocrLanguages: TextRecognizing.languages)
        }
        report.add("RTF_EXTRAKTION", "ms=\(msOf(started.duration(to: .now))) "
                   + "via=\(extracted?.via.rawValue ?? "keine") seiten=\(extracted?.pages.map(String.init) ?? "-") "
                   + "zeichen=\(extracted?.chars ?? -1) budget=\(extracted?.text.contains("85.000") == true) "
                   + "keine_rtf_klammern=\(extracted?.text.contains("rtf1") == false) "
                   + "text=\(TextLine.oneLine(extracted?.text ?? "", limit: 160))")

        let stored = documents.store(url: url)
        if let stored {
            documents.writeText(extracted?.text ?? "", for: stored.file)
            report.add("RTF_ABLAGE", "name=\(stored.file) bytes=\(stored.bytes) "
                       + "text_wieder=\(documents.text(named: stored.file) == extracted?.text) "
                       + "beleg_da=\(documents.storedURL(for: stored.file) != nil)")
        }
        let meta = AttachedFile(file: stored?.file ?? "", name: "Notiz.rtf", kind: .rtf,
                                bytes: stored?.bytes ?? 0, chars: extracted?.chars ?? 0, via: .richText)
        report.add("RTF_KARTE", "badge=\(FileGlyph.label(for: .rtf)) "
                   + "zeilen=\(TextLine.oneLine(meta.metaText, limit: 160)) "
                   + "pill=\(FileRef(meta).privacyKey ?? "-")")

        guard store.current != nil else {
            report.add("RTF_KETTE", "keine unterhaltung")
            return
        }
        store.newConversation()
        guard let probeConv = store.current?.id else {
            report.add("RTF_KETTE", "keine frische unterhaltung")
            return
        }
        let pending = PendingFile(name: "Notiz.rtf", kind: .rtf, file: stored?.file ?? "",
                                  bytes: stored?.bytes ?? 0, chars: extracted?.chars ?? 0,
                                  via: extracted?.via ?? .richText, reading: false)
        view.pendingFiles = [pending]
        view.input = "Was steht in der RTF-Notiz zum Lager-Budget? Ein Satz."
        let turn = await sentTurn(view)
        let question = turn.question
        let answer = turn.answer
        report.add("RTF_KETTE", "ms=\(turn.ms) anhang_dateien=\(question?.files.count ?? -1) "
                   + "chips=\(answer?.fileRefs?.count ?? -1) chip=\(answer?.fileRefs?.first?.chipText ?? "-") "
                   + "budget_in_antwort=\(answer?.text.contains("85.000") == true) "
                   + "text=\(TextLine.oneLine(answer?.text ?? "", limit: 160))")
        store.cleaner.deleteConversation(probeConv)
        store.cleaner.discardPendingDeletion()
        report.add("RTF_ENDGÜLTIG", "rtf_weg=\(documents.storedURL(for: pending.file) == nil) "
                   + "text_weg=\(documents.text(named: pending.file) == nil)")
        flowLog.info("RTFTEST fertig")
    }

    private static func rtfScanTest(_: ChatView) async {
        let report = SweepReport(file: "rtf_scan.txt")
        let url = scannedRTF()
        defer { try? FileManager.default.removeItem(at: url) }
        let pictures = (try? Data(contentsOf: url)).map { RichTextFile.pictures(in: $0).count } ?? -1
        let found = await scanExtraction(from: url, kind: .rtf)
        report.add("RTF_SCAN_OCR", "bilder=\(pictures) " + scanFindings(found))
        flowLog.info("RTFSCANTEST fertig")
    }

    private static func dropFixture(named name: String) -> URL? {
        let folder = StoragePaths().documents.appendingPathComponent("dropfixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        switch name {
        case "brief.docx": return writeDropDocx(to: url)
        case "protokoll.pdf": return writeDropPDF(to: url)
        case "foto.jpg": return writeDropJPEG(to: url)
        default: return nil
        }
    }

    private static func writeDropDocx(to url: URL) -> URL? {
        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
        <w:p><w:r><w:t>Angebot Nr. 2026-17 - Ausbau Lagerhalle</w:t></w:r></w:p>
        <w:p><w:r><w:t>Der Ausbau des Lagers kostet insgesamt 85.000 Euro brutto.</w:t></w:r></w:p>
        <w:p><w:r><w:t>Fertigstellung ist fuer den 03.07.2026 geplant.</w:t></w:r></w:p>
        <w:p><w:r><w:t>Ansprechpartnerin: Frau Berger, Telefon 0731 555 1234.</w:t></w:r></w:p>
        </w:body></w:document>
        """
        let types = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        let archive = storedZip([(name: "[Content_Types].xml", data: Data(types.utf8)),
                                 (name: "_rels/.rels", data: Data(rels.utf8)),
                                 (name: "word/document.xml", data: Data(document.utf8))])
        guard (try? archive.write(to: url)) != nil else { return nil }
        return url
    }

    private static func writeDropPDF(to url: URL) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 420, height: 595))
        let data = renderer.pdfData { context in
            context.beginPage()
            NSAttributedString(string: "Protokoll der Sitzung: Ausbau Lagerhalle", attributes: [
                .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
            ]).draw(in: CGRect(x: 30, y: 40, width: 360, height: 60))
            NSAttributedString(string: "Budget 85.000 Euro, Beschluss vom 12.05.2026.", attributes: [
                .font: UIFont.systemFont(ofSize: 20),
            ]).draw(in: CGRect(x: 30, y: 110, width: 360, height: 80))
        }
        guard (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    private static func writeDropJPEG(to url: URL) -> URL? {
        guard let data = receiptImage().jpegData(compressionQuality: 0.85) else { return nil }
        guard (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    private static func storedZip(_ entries: [(name: String, data: Data)]) -> Data {
        var payload = Data()
        var central = Data()
        for entry in entries {
            let offset = payload.count
            payload.append(zipLE32(0x0403_4B50))
            payload.append(zipLE16(20))
            payload.append(zipLE16(0))
            payload.append(zipLE16(0))
            payload.append(zipLE16(0))
            payload.append(zipLE16(0))
            payload.append(zipLE32(0))
            payload.append(zipLE32(entry.data.count))
            payload.append(zipLE32(entry.data.count))
            payload.append(zipLE16(entry.name.utf8.count))
            payload.append(zipLE16(0))
            payload.append(contentsOf: entry.name.utf8)
            payload.append(entry.data)
            central.append(zipLE32(0x0201_4B50))
            central.append(zipLE16(20))
            central.append(zipLE16(20))
            central.append(zipLE16(0))
            central.append(zipLE16(0))
            central.append(zipLE16(0))
            central.append(zipLE16(0))
            central.append(zipLE32(0))
            central.append(zipLE32(entry.data.count))
            central.append(zipLE32(entry.data.count))
            central.append(zipLE16(entry.name.utf8.count))
            central.append(zipLE16(0))
            central.append(zipLE16(0))
            central.append(zipLE16(0))
            central.append(zipLE16(0))
            central.append(zipLE32(0))
            central.append(zipLE32(offset))
            central.append(contentsOf: entry.name.utf8)
        }
        var archive = payload
        let centralOffset = archive.count
        archive.append(central)
        archive.append(zipLE32(0x0605_4B50))
        archive.append(zipLE16(0))
        archive.append(zipLE16(0))
        archive.append(zipLE16(entries.count))
        archive.append(zipLE16(entries.count))
        archive.append(zipLE32(central.count))
        archive.append(zipLE32(centralOffset))
        archive.append(zipLE16(0))
        return archive
    }

    private static func zipLE16(_ value: Int) -> Data {
        Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff)])
    }

    private static func zipLE32(_ value: Int) -> Data {
        Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff),
              UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)])
    }

    private static func prepareDropProvider(_ view: ChatView) async -> Int {
        let settings = view.settings
        guard settings.isConfigured else { return -1 }
        var waited = 0
        while settings.chatModel.isEmpty, waited < 90 {
            try? await Task.sleep(for: .seconds(1))
            waited += 1
        }
        return settings.chatModel.isEmpty ? -1 : waited
    }

    private static func waitForDroppedAnswer(_ view: ChatView, in conversation: UUID,
                                             seconds: Int) async -> (Int, ChatMessage?) {
        var waited = 0
        while waited < seconds {
            try? await Task.sleep(for: .seconds(1))
            waited += 1
            if let answer = view.store.current?.messages.last(where: { $0.role == .assistant }) {
                return (waited, answer)
            }
            if view.store.current?.id != conversation { return (waited, nil) }
        }
        return (waited, nil)
    }

    private static func dropScenario(_ view: ChatView, files: [String], report file: String) async {
        let report = SweepReport(file: file)
        let modelWait = await prepareDropProvider(view)
        guard modelWait >= 0 else {
            report.add("MODELL", "kein KI-Anbieter konfiguriert")
            report.add("ABLAUF", "uebersprungen: keine Konfiguration geaendert")
            report.add("ENDE", "ok")
            flowLog.info("DROPTEST \(file, privacy: .public) ohne provider")
            return
        }
        report.add("MODELL", "provider=\(view.settings.provider.rawValue) "
                   + "konfiguriert=\(view.settings.isConfigured) chat=\(view.settings.chatModel) "
                   + "vision=\(view.settings.visionModel) warten_s=\(modelWait)")
        var urls: [URL] = []
        for name in files {
            guard let url = dropFixture(named: name) else {
                report.add("LAGE", "fixture fehlt: \(name)")
                continue
            }
            let bytes = (try? Data(contentsOf: url))?.count ?? -1
            report.add("ART", "name=\(name) bytes=\(bytes) "
                       + "art=\(String(describing: DropPolicy.item(forFileNamed: name)))")
            urls.append(url)
        }
        guard !urls.isEmpty else {
            flowLog.error("DROPTEST \(file, privacy: .public) ohne fixture")
            return
        }
        view.store.newConversation()
        guard let conversation = view.store.current?.id else {
            report.add("ABLAUF", "keine frische unterhaltung")
            return
        }
        let started = ContinuousClock.now
        view.acceptDroppedFiles(urls)
        let (waited, answer) = await waitForDroppedAnswer(view, in: conversation, seconds: 180)
        let messages = view.store.current?.messages ?? []
        let question = messages.last(where: { $0.role == .user })
        report.add("ABLAUF", "ms=\(msOf(started.duration(to: .now))) warten_s=\(waited) "
                   + "frage_da=\(question != nil) antwort_da=\(answer != nil) "
                   + "fehler=\(view.probeAlerts.count)")
        if let question {
            let fileList = question.files
                .map { "\($0.name):\($0.chars):\($0.via.rawValue)" }
                .joined(separator: ",")
            report.add("FRAGE", "text=\(TextLine.oneLine(question.text, limit: 160)) "
                       + "dateien=\(fileList) bilder=\(question.images.count)")
        }
        if let answer {
            report.add("ANTWORT", "zeichen=\(answer.text.count) text=\(TextLine.oneLine(answer.text, limit: 260))")
        }
        for alert in view.probeAlerts {
            report.add("HINWEIS", "\(alert.message) | \(alert.detail)")
        }
        view.store.cleaner.deleteConversation(conversation)
        view.store.cleaner.discardPendingDeletion()
        flowLog.info("DROPTEST \(file, privacy: .public) fertig")
    }

    private static func ocrTest(_ view: ChatView) async {
        let report = SweepReport(file: "ocr_test.txt")
        let shot = receiptImage()
        let payload = shot.jpegData(compressionQuality: 0.8)
        let started = ContinuousClock.now
        var direct: String? = nil
        if let data = payload {
            direct = await Offload.orNilFlat {
                TextRecognizing.recognize(data: data, languages: ["de-DE", "en-US"])
            }
        }
        report.add("VISION", "ms=\(msOf(started.duration(to: .now))) zeichen=\(direct?.count ?? -1) "
                   + "kaffee=\(direct?.uppercased().contains("KAFFEE") == true) "
                   + "betrag=\(direct?.contains("14,80") == true) "
                   + "text=\(TextLine.oneLine(direct ?? "", limit: 160))")

        let previous = view.settings.autoOCR
        let offPicture = PendingPicture(image: shot, file: nil)
        view.pendingImages = [offPicture]
        view.settings.autoOCR = false
        view.runOCR(on: [offPicture])
        try? await Task.sleep(for: .seconds(3))
        report.add("AUTO_AUS", "karte=\(view.pendingImages.first?.ocrFile == nil ? "keine" : "unerwartet")")

        view.settings.autoOCR = true
        let picture = PendingPicture(image: shot, file: nil)
        view.pendingImages = [picture]
        view.runOCR(on: [picture])
        var waited = 0
        while view.pendingImages.first?.ocrFile == nil, waited < 30 {
            try? await Task.sleep(for: .milliseconds(500))
            waited += 1
        }
        guard let saved = view.pendingImages.first?.ocrFile else {
            report.add("ABLAGE", "keine datei nach \(waited) halbticks")
            view.pendingImages = []
            view.settings.autoOCR = previous
            return
        }
        report.add("ABLAGE", "name=\(saved.displayName) zeichen=\(saved.chars) "
                   + "halbticks=\(waited) im_speicher=\(OcrTextCache.shared.text(for: saved.file) != nil) "
                   + "documents_datei=\(FileManager.default.fileExists(atPath: OcrTextStore.documentsURL(for: saved.file).path)) "
                   + "ordner=\(OcrTextStore.folder)")

        view.store.newConversation()
        view.input = "Was ist auf dem Foto?"
        let turn = await sentTurn(view)
        let messages = turn.messages
        let question = turn.question
        let answer = turn.answer
        let media = view.store.media
        let chat = ConversationMemory.turn(from: messages,
                                           load: { media.data(for: $0) },
                                           fileText: { view.store.documents.text(named: $0) })
        let asked = chat.messages.first(where: { $0.role == .user })
        report.add("KETTE", "ms=\(turn.ms) ocr_anhang=\(question?.ocrFiles?.count ?? -1) "
                   + "frage_ocr=\(asked?.text.contains("KAFFEE") == true) "
                   + "antwort=\(TextLine.oneLine(answer?.text ?? "", limit: 160)) "
                   + "vision=\(chat.needsVision)")

        view.settings.autoOCR = false
        view.pendingImages = [PendingPicture(image: shot, file: nil)]
        let lone = ContinuousClock.now
        await view.send()
        let loneMessages = view.store.current?.messages ?? []
        let loneAnswer = loneMessages.last(where: { $0.role == .assistant })
        report.add("NUR_BILD", "ms=\(msOf(lone.duration(to: .now))) nachrichten=\(loneMessages.count) "
                   + "erzeugte_bilder=\(loneAnswer?.outImages?.count ?? -1) "
                   + "antwort_chars=\(loneAnswer?.text.count ?? -1) "
                   + "text=\(TextLine.oneLine(loneAnswer?.text ?? "", limit: 140))")
        view.pendingImages = []
        view.settings.autoOCR = previous
        if let id = view.store.current?.id {
            view.store.cleaner.deleteConversation(id)
            view.store.cleaner.discardPendingDeletion()
        }
        report.add("OCR_TEXT_Bleibt", "im_speicher=\(OcrTextCache.shared.text(for: saved.file) != nil) "
                   + "documents_ordner_da=\(FileManager.default.fileExists(atPath: StoragePaths().storedOCRBeforeMove.path)) "
                   + "eigener_ordner_da=\(FileManager.default.fileExists(atPath: StoragePaths().ocr.path)) "
                   + "tmp_ordner_da=\(FileManager.default.fileExists(atPath: OcrTextStore.temporaryRoot.path))")
        guard let cached = OcrTextCache.shared.text(for: saved.file) else {
            flowLog.info("OCRTEST ohne text im speicher")
            return
        }
        let handed = OcrTextStore.temporaryFile(named: saved.file, text: cached)
        report.add("SPEICHERN", "tmp_da=\(handed.map { FileManager.default.fileExists(atPath: $0.path) } ?? false) "
                   + "in_documents=\(handed.map { $0.path.hasPrefix(StoragePaths().documents.path) } ?? false) "
                   + "zeichen=\(handed.flatMap { try? String(contentsOf: $0, encoding: .utf8) }?.count ?? -1)")
        flowLog.info("OCRTEST fertig")
    }
}
#endif
