@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
#if DEBUG
import GwenMobileKit
import UIKit

extension DebugFeatureProbe {
    static func shareProbe(_ view: ChatView) async {
        let report = SweepReport(file: "share_probe.txt")
        view.store.newConversation()
        view.input = "Nenne drei Hauptstädte mit je einem Satz."
        await view.send()
        let answer = view.store.current?.messages.last(where: { $0.role == .assistant })
        do {
            let url = try AnswerExporter().write(text: answer?.text ?? "", sources: answer?.sources ?? [],
                                                question: "Drei Hauptstädte", model: answer?.model,
                                                elapsed: answer?.elapsed, time: nil)
            report.add("DATEI", "name=\(url.lastPathComponent) bytes=\((try? Data(contentsOf: url))?.count ?? -1)")
            try Presenter.share(url: url)
            var sheet: UIActivityViewController?
            _ = await ProbeWait.until(8) {
                sheet = Presenter.topViewController as? UIActivityViewController
                return sheet != nil
            }
            report.add("FENSTER", "sichtbar=\(sheet != nil)")
            sheet?.dismiss(animated: true)
            _ = await ProbeWait.until(5) { Presenter.topViewController is UIActivityViewController == false }
            report.add("WIEDER_CHAT", "blatt_fort=\(Presenter.topViewController is UIActivityViewController == false)")
        } catch {
            report.addFailure("TEILEN", error)
        }
        flowLog.info("TEILEN fertig")
    }

    static func undoFlow(_ view: ChatView) async {
        let report = SweepReport(file: "undo_flow.txt")
        let cleaner = view.store.cleaner
        await cleaner.refreshUsage()
        report.add("NUTZUNG", "unterhaltungen=\(cleaner.usage.conversations) nachrichten=\(cleaner.usage.messages) "
                   + "bilder=\(cleaner.usage.imageFiles) bytes=\(cleaner.usage.imageBytesText)")
        await galleryCheck(view, cleaner, report)
        guard let target = view.store.conversations.first(where: { $0.messages.count > 1 }) else {
            report.add("LÖSCHEN", "keine geeignete unterhaltung")
            return
        }
        let id = target.id
        let nachrichten = target.messages.count
        cleaner.deleteConversation(id)
        report.add("GELÖSCHT", "beleg=\(cleaner.receipt != nil) "
                   + "weg=\(view.store.conversations.contains { $0.id == id } == false)")
        cleaner.undoLast()
        report.add("ZURÜCKHOLEN", "wiederDa=\(countOf(view, id: id) > 0) nachrichten=\(countOf(view, id: id)) erwartet=\(nachrichten)")
        guard let first = view.store.conversations.first(where: { $0.id == id })?.messages.first else {
            return
        }
        cleaner.deleteMessage(first.id, in: id)
        report.add("NACHRICHT_WEG", "beleg=\(cleaner.receipt != nil) nachrichten=\(countOf(view, id: id))")
        cleaner.undoLast()
        report.add("NACHRICHT_ZURÜCK", "nachrichten=\(countOf(view, id: id))")
        await cleaner.refreshUsage()
        report.add("NUTZUNG_ENDE", "unterhaltungen=\(cleaner.usage.conversations) nachrichten=\(cleaner.usage.messages)")
        flowLog.info("RÜCKGÄNGIG fertig")
    }

    private static func galleryCheck(_ view: ChatView, _ cleaner: HistoryCleaner,
                                     _ report: SweepReport) async {
        guard let file = view.store.media.storeImageData(Data([1, 2, 3])) else {
            report.add("GALERIE_BILDER", "kein bild")
            return
        }
        view.store.newConversation()
        guard let id = view.store.currentID else { return }
        let picture = WebPicture(file: file, pageURL: "https://example.test/a",
                                 fullURL: "https://example.test/a.jpg", title: "A", domain: "example.test")
        let gallery = PictureGallery(query: "A", pictures: [picture], shown: 1,
                                     nextOffset: 2, exhausted: true)
        view.store.appendMessage(ChatMessage(role: .assistant, text: "", gallery: gallery), to: id)
        await cleaner.refreshUsage()
        let count = view.store.current.map(HistoryView.imageCount) ?? -1
        report.add("GALERIE_BILDER", "anzahl=\(count) bytes=\(cleaner.usage.bytesByConversation[id] ?? -1)")
        cleaner.deleteConversation(id)
        cleaner.discardPendingDeletion()
    }

    static func countOf(_ view: ChatView, id: UUID) -> Int {
        view.store.conversations.first(where: { $0.id == id })?.messages.count ?? -1
    }

    static func historyWipe(_ view: ChatView) async {
        let report = SweepReport(file: "history_wipe.txt")
        let store = view.store
        let stored = store.media.store(PictureProbe.star.image())
        if let stored, let seeded = store.currentID {
            store.appendMessage(ChatMessage(role: .user, text: "Frage mit Bild",
                                            images: [Attachment(file: stored)]), to: seeded)
            store.appendAssistant("Antwort mit Bild", model: "probe", elapsed: nil, to: seeded,
                                  outImages: [Attachment(file: stored)])
        }
        let conversationsBefore = store.conversations.count
        let filesBefore = store.media.fileNames().count
        let first = store.currentID
        if let first { store.cleaner.deleteConversation(first) }
        report.add("EINZELLÖSCHUNG", "vorher=\(conversationsBefore) nachher=\(store.conversations.count) "
                   + "beleg=\(store.cleaner.receipt?.conversations.count ?? -1) "
                   + "freigegebene_dateien=\(store.cleaner.receipt?.freedFiles ?? -1) "
                   + "datei_weg=\(stored.map { String(store.media.data(named: $0) == nil) } ?? "-")")
        store.cleaner.undoLast()
        report.add("EINZELLÖSCHUNG_UNDO", "unterhaltungen=\(store.conversations.count) "
                   + "dateien=\(store.media.fileNames().count) vorher_dateien=\(filesBefore) "
                   + "wieder_da=\(stored.map { String(store.media.data(named: $0) != nil) } ?? "-")")
        view.store.newConversation()
        guard let doomed = store.currentID else {
            report.add(" abbruch", "keine aktuelle unterhaltung")
            return
        }
        store.appendAssistant("Löschtest-Antwort", model: "probe", elapsed: nil, to: doomed)
        let messageCount = store.conversations.first { $0.id == doomed }?.messages.count ?? -1
        if let last = store.conversations.first(where: { $0.id == doomed })?.messages.last {
            store.cleaner.deleteMessage(last.id, in: doomed)
        }
        report.add("NACHRICHT_LÖSCHUNG", "vorher=\(messageCount) "
                   + "nachher=\(store.conversations.first { $0.id == doomed }?.messages.count ?? -1)")
        store.cleaner.undoLast()
        report.add("NACHRICHT_UNDO",
                   "nachher=\(store.conversations.first { $0.id == doomed }?.messages.count ?? -1)")
        let openBefore = store.currentID
        store.cleaner.deleteAllConversations()
        report.add("ALLE_LÖSCHUNG", "unterhaltungen=\(store.conversations.count) "
                   + "aktuellVorher=\(String(describing: openBefore)) aktuell=\(String(describing: store.currentID)) "
                   + "beleg=\(store.cleaner.receipt?.conversations.count ?? -1) "
                   + "dateien=\(store.cleaner.receipt?.freedFiles ?? -1) "
                   + "bytes=\(store.cleaner.receipt?.freedBytes ?? -1) "
                   + "speicher=\(store.cleaner.usage.summaryText)")
        store.cleaner.undoLast()
        report.add("ALLE_UNDO", "unterhaltungen=\(store.conversations.count) "
                   + "aktuell=\(String(describing: store.currentID)) wiederher=\(store.currentID == openBefore)")
        store.cleaner.deleteAllConversations()
        _ = await ProbeWait.until(30) { store.cleaner.receipt == nil }
        report.add("ALLE_ENDGÜLTIG", "unterhaltungen=\(store.conversations.count) "
                   + "beleg_offen=\(store.cleaner.receipt != nil)")
        let trashFiles = (try? FileManager.default.contentsOfDirectory(atPath: store.media.paths.trash.path)) ?? []
        report.add("TRASH_LEER", "dateien=\(trashFiles.count)")
        flowLog.info("HISTORYWIPE fertig")
    }

}
#endif
