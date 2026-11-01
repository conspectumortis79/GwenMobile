@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import PDFKit
import UIKit

@MainActor
enum DebugScanProbe {
    private struct RouteCase {
        let sentence: String
        var kind: ScanKind? = nil
        var remind = false
        var forbidden = false
    }

    private static let routeCases = [
        RouteCase(sentence: "Rechnung scannen", kind: .invoice),
        RouteCase(sentence: "Kassenbon scannen", kind: .receipt),
        RouteCase(sentence: "Behördenschreiben scannen", kind: .authority),
        RouteCase(sentence: "Brief abfotografieren und zusammenfassen", kind: .letter),
        RouteCase(sentence: "Frist als Erinnerung scannen", remind: true),
        RouteCase(sentence: "Scan the receipt", kind: .receipt),
        RouteCase(sentence: "Quiero escanear la factura", kind: .invoice),
        RouteCase(sentence: "Wie scanne ich ein Dokument mit dem iPhone?", forbidden: true),
        RouteCase(sentence: "Was ist ein Kassenbon?", forbidden: true)
    ]

    static func routing(_ view: ChatView) async {
        await RouteSweep.routeAll(routeCases, file: "scan_route.txt", view: view,
                                  log: "SCANROUTING fertig",
                                  fits: { fitting($0, plan: $1) },
                                  label: expectedLabel, sentence: { $0.sentence },
                                  detail: describe,
                                  requiresKey: true, abortLog: "SCANROUTING abbruch")
    }

    static func flow(_ view: ChatView) async {
        let report = SweepReport(file: "scan_flow.txt")
        let documents = view.store.documents
        report.add("KAMERA", "visionkit=\(DocumentScanner.shared.isSupported) "
                   + "kamera=\(CameraPresenter.shared.isAvailable)")
        let pages = [ReceiptCard.receiptCard(fontSize: 46), ReceiptCard.receiptCard(fontSize: 46)]
        let workflow = ScanWorkflow()
        let started = ContinuousClock.now
        let outcome = await Offload.orNilFlat {
            workflow.store(pages: pages, kind: .receipt, date: Date(), documents: documents)
        }
        guard let outcome else {
            report.add("SCAN", "fehlgeschlagen")
            flowLog.info("SCANFLOW fehlgeschlagen")
            return
        }
        let upper = outcome.text.uppercased()
        report.add("SCAN", "ms=\(msOf(started.duration(to: .now))) datei=\(outcome.attachment.file) "
                   + "name=\(outcome.attachment.name) seiten=\(outcome.attachment.pages.map(String.init) ?? "-") "
                   + "kind=\(outcome.attachment.kind.rawValue) via=\(outcome.attachment.via.rawValue) "
                   + "zeichen=\(outcome.attachment.chars) kaffee=\(upper.contains("KAFFEE")) "
                   + "betrag=\(outcome.text.contains("14,80")) seite2=\(outcome.text.contains("--- page 2 ---"))")
        let url = documents.storedURL(for: outcome.attachment.file)
        let copied = documents.paths.downloads.appendingPathComponent(outcome.attachment.name)
        report.add("PDF", "da=\(url != nil) seiten=\(url.flatMap { PDFDocument(url: $0)?.pageCount } ?? -1)")
        report.add("DATEIEN", "downloads_da=\(FileManager.default.fileExists(atPath: copied.path)) "
                   + "ort=\(copied.path)")
        report.add("SIDECAR", "text_gleich=\(documents.text(named: outcome.attachment.file) == outcome.text) "
                   + "karte=\(TextLine.oneLine(outcome.attachment.metaText, limit: 120))")
        report.add("TEXT", TextLine.oneLine(outcome.text, limit: 200))
        documents.discardStored([outcome.attachment.file])
        try? FileManager.default.removeItem(at: copied)
        report.add("AUFRAEUMEN", "datei_weg=\(documents.storedURL(for: outcome.attachment.file) == nil) "
                   + "downloads_weg=\(!FileManager.default.fileExists(atPath: copied.path))")
        flowLog.info("SCANFLOW fertig")
    }

    static func chat(_ view: ChatView) async {
        let report = SweepReport(file: "scan_chat.txt")
        let settings = view.settings
        guard settings.isConfigured else {
            report.add("ABBRUCH", "kein schluessel")
            flowLog.info("SCANCHAT abbruch")
            return
        }
        let documents = view.store.documents
        let media = view.store.media
        let workflow = ScanWorkflow()
        let pages = [ReceiptCard.receiptCard(fontSize: 46)]
        let outcome = await Offload.orNilFlat {
            workflow.store(pages: pages, kind: .receipt, date: Date(), documents: documents)
        }
        guard let outcome else {
            report.add("SCAN", "fehlgeschlagen")
            flowLog.info("SCANCHAT fehlgeschlagen")
            return
        }
        let before = Set(view.store.conversations.map(\.id))
        let previous = view.store.currentID
        let text = "Kassenbon scannen"
        let request = ScanRequest(kind: .receipt, remind: false)
        view.store.newConversation()
        guard let convID = view.store.current?.id else {
            report.add("KETTE", "keine frische unterhaltung")
            return
        }
        view.store.appendMessage(ChatMessage(role: .user, text: text), to: convID)
        guard let messageID = view.store.current?.messages.last?.id else {
            report.add("KETTE", "keine nachricht")
            return
        }
        view.store.attachScan(outcome.attachment, to: messageID, in: convID)
        let messages = view.store.current?.messages ?? []
        guard var turn = await Offload.orNil({
            ConversationMemory.turn(from: messages, load: { media.data(for: $0) },
                                    fileText: { documents.text(named: $0) })
        }) else {
            report.add("KETTE", "kein turn")
            return
        }
        ScanAnswers.injectInstruction(into: &turn.messages, for: request)
        let model = settings.answeringModel(hasPictures: turn.needsVision)
        let thinking = settings.thinkingOffDirective(for: model)
        let catalog = settings.memory.enabled ? await view.store.memory.catalog() : ""
        let plan = await ToolRouter.plan(RouterAsk(baseURL: settings.baseURL, key: settings.apiKey, model: model,
                                                   text: text, context: SendContext(scannedDocument: true),
                                                   history: messages, catalog: catalog,
                                                   document: outcome.text, thinking: thinking))
        let actions = ScanPlan.analysisActions(plan, remind: false)
        report.add("ROUTER", "roh=\(plan.traceLine) scan_roh=\(plan.actions.contains { $0.stepKind == .scan }) "
                   + "gefiltert=\(actions.map(\.stepKind.rawValue).joined(separator: "+")) "
                   + "scan_danach=\(actions.contains { $0.stepKind == .scan })")

        await view.streamChat(turn: turn, history: messages, convID: convID, started: Date())
        let answer = view.store.current?.messages.last(where: { $0.role == .assistant })
        let answerUpper = (answer?.text ?? "").uppercased()
        report.add("ANTWORT", "zeichen=\(answer?.text.count ?? -1) kaffee=\(answerUpper.contains("KAFFEE")) "
                   + "betrag=\(answerUpper.contains("14,80") || answerUpper.contains("14.80")) "
                   + "chips=\(answer?.fileRefs?.count ?? -1) "
                   + "chip=\(answer?.fileRefs?.first?.chipText ?? "-") "
                   + "automatisch_erstellt=\(answer?.reminderRef != nil) "
                   + "text=\(TextLine.oneLine(answer?.text ?? "", limit: 220))")

        let invoiceText = "STADTWERKE MÜNCHEN\nRechnung 2026-88-421\nGesamtbetrag 84,20 €\n"
            + "Zahlbar bis 15.10.2026"
        let reminder = await ToolRouter.scanReminder(baseURL: settings.baseURL, key: settings.apiKey,
                                                     model: model, text: "Frist als Erinnerung scannen",
                                                     context: SendContext(scannedDocument: true,
                                                                          documentReminder: true),
                                                     history: messages, document: invoiceText,
                                                     catalog: catalog, thinking: thinking)
        let copied = documents.paths.downloads.appendingPathComponent(outcome.attachment.name)
        if let answerID = answer?.id {
            view.store.attachScanRef(outcome.attachment, to: answerID, in: convID)
            let stored = view.store.current?.messages.first(where: { $0.id == answerID })
            report.add("PDF", "scanref_da=\(stored?.scanRef != nil) name=\(stored?.scanRef?.name ?? "-") "
                       + "downloads_da=\(FileManager.default.fileExists(atPath: copied.path))")
        }
        if case .reminder(let reminderPlan) = reminder?.route,
           let offer = ScanReminderOffer(from: reminderPlan),
           let answerID = answer?.id {
            view.store.attachReminderOffer(offer, to: answerID, in: convID)
            let stored = view.store.current?.messages.first(where: { $0.id == answerID })
            report.add("ANGEBOT", "titel=\(offer.title) faellig=\(offer.chipStamp ?? "-") "
                       + "angebot_da=\(stored?.reminderOffer != nil) "
                       + "automatisch_erstellt=\(stored?.reminderRef != nil)")
            let runner = view.reminderDesk.runner()
            if let request = offer.request {
                let made = await runner.run(request)
                report.add("TASTE", "erstellt=\(made.ref != nil) liste=\(made.ref?.list ?? "-") "
                           + "faellig=\(made.ref?.due.map(Formatters.eventDateTime) ?? "-") "
                           + "text=\(TextLine.oneLine(made.text, limit: 140))")
                if let ref = made.ref {
                    try? await EventKitReminderStore().delete(ref.reminderID)
                    let open = (try? await EventKitReminderStore().open()) ?? []
                    report.add("AUFRAEUMEN_ERINNERUNG",
                               "geloescht=\(!open.contains { $0.id == ref.reminderID })")
                }
            }
        } else {
            report.add("ANGEBOT", "keins: \(reminder?.stepKind.rawValue ?? "nichts")")
        }

        for conversation in view.store.conversations where !before.contains(conversation.id) {
            view.store.cleaner.deleteConversation(conversation.id)
        }
        view.store.cleaner.discardPendingDeletion()
        documents.discardStored([outcome.attachment.file])
        try? FileManager.default.removeItem(at: copied)
        if let previous, view.store.conversations.contains(where: { $0.id == previous }) {
            view.store.currentID = previous
        }
        report.add("AUFRAEUMEN", "datei_weg=\(documents.storedURL(for: outcome.attachment.file) == nil) "
                   + "downloads_weg=\(!FileManager.default.fileExists(atPath: copied.path)) "
                   + "unterhaltungen_zurueck=\(view.store.conversations.count >= before.count)")
        flowLog.info("SCANCHAT fertig")
    }

    private static func expectedLabel(_ item: RouteCase) -> String {
        if item.forbidden { return "kein scan" }
        let kind = item.kind?.rawValue ?? "beliebig"
        return "scan \(kind)" + (item.remind ? " erinnerung" : "")
    }

    private static func describe(_ plan: SendPlan) -> String {
        guard case .scanDocument(let request) = plan.primary.route else { return plan.traceLine }
        return "art=\(request.kind.rawValue) erinnerung=\(request.remind)"
    }

    private static func fitting(_ item: RouteCase, plan: SendPlan) -> Bool {
        if item.forbidden { return plan.primary.stepKind != .scan }
        guard plan.primary.stepKind == .scan,
              case .scanDocument(let request) = plan.primary.route else { return false }
        if let kind = item.kind, request.kind != kind { return false }
        if item.remind, !request.remind { return false }
        return true
    }
}
#endif
