import GwenMobileKit
import SwiftUI

extension ChatView {
    @MainActor func startMenuScan() async {
        guard !Task.isCancelled else { return }
        guard settings.isConfigured else { showSettings = true; return }
        if store.current == nil { store.newConversation() }
        guard let convID = store.current?.id else { return }
        await runExclusiveBusy {
            await runScanFlow(ScanRequest(kind: .other, remind: false),
                              convID: convID, started: Date(), slot: nil)
        }
    }

    @MainActor private func runExclusiveBusy(_ work: @MainActor @escaping () async -> Void) async {
        guard !isBusy, !isStreaming, runTask == nil else { return }
        AppSettings.flushKeySave()
        runGeneration += 1
        let generation = runGeneration
        let task = Task { @MainActor in
            isBusy = true
            defer { if generation == runGeneration { isBusy = false } }
            await work()
        }
        runTask = task
        await task.value
        if generation == runGeneration { runTask = nil }
    }

    @MainActor func runScanFlow(_ request: ScanRequest, convID: UUID,
                                started: Date, slot: AnswerSlot?,
                                triggerMessageID: UUID? = nil) async {
        guard !Task.isCancelled else { return }
        flowMark("SCAN start art=\(request.kind.rawValue) erinnerung=\(request.remind) "
                 + "kamera=\(DocumentScanner.shared.isSupported)")
        guard DocumentScanner.shared.isSupported || CameraPresenter.shared.isAvailable else {
            flowMark("SCAN keine kamera")
            appendFailure(ScanAnswers.unavailable, model: settings.chatModel,
                          convID: convID, started: started, slot: slot)
            return
        }
        guard let pages = await DocumentScanner.shared.scan() else {
            guard !Task.isCancelled else { return }
            flowMark("SCAN abgebrochen")
            appendFailure(ScanAnswers.cancelled, model: settings.chatModel,
                          convID: convID, started: started, slot: slot)
            return
        }
        guard !Task.isCancelled else { return }
        let documents = store.documents
        let workflow = scanWorkflow
        let outcome = await busy.running(L.t("scan_reading"), {
            await Offload.orNilFlat {
                workflow.store(pages: pages, kind: request.kind, date: Date(), documents: documents)
            }
        })
        guard !Task.isCancelled else { return }
        guard let outcome else {
            flowMark("SCAN auswertung fehlgeschlagen")
            appendFailure(ScanAnswers.failed, model: settings.chatModel,
                          convID: convID, started: started, slot: slot)
            return
        }
        if let previous = pendingScan {
            pendingScan = nil
            pendingFiles.removeAll { $0.id == previous.file.id }
            store.documents.discardStored([previous.outcome.attachment.file])
        }
        guard pendingFiles.count < FilePolicy.maxFilesPerMessage else {
            store.documents.discardStored([outcome.attachment.file])
            queueAlert(L.FriendlyError(message: L.n("file_limit", FilePolicy.maxFilesPerMessage),
                                       detail: "", openSettings: false))
            return
        }
        let pending = PendingScan(outcome: outcome, request: request)
        pendingFiles.append(pending.file)
        pendingScan = pending
        if let triggerMessageID {
            _ = store.removeMessage(triggerMessageID, from: convID)
        }
        inputFocused = true
        flowMarkPersonal("SCAN bereit art=\(request.kind.rawValue) "
                         + "datei=\(outcome.attachment.file) seiten=\(outcome.attachment.pages ?? -1) "
                         + "zeichen=\(outcome.attachment.chars)")
    }

    @MainActor func analyzeScan(_ outcome: ScanOutcome, request: ScanRequest, text: String,
                                        convID: UUID, slot: AnswerSlot?, number: Int) async {
        guard !Task.isCancelled else { return }
        let freshHistory = store.conversations.first(where: { $0.id == convID })?.messages ?? []
        let priorCount = freshHistory.count
        let documents = store.documents
        let media = store.media
        guard let turn = await Offload.orNil({
            ConversationMemory.turn(from: freshHistory, load: { media.data(for: $0) },
                                    fileText: { documents.text(named: $0) })
        }) else { return }
        guard !Task.isCancelled else { return }
        let context = SendContext(scannedDocument: true, documentReminder: request.remind)
        let ask = await routerAsk(text, context: context, history: freshHistory, needsVision: turn.needsVision,
                                  document: outcome.text)
        let plan = await busy.running(L.t("scan_analyzing"), { await ToolRouter.plan(ask) })
        guard !Task.isCancelled else { return }
        let actions = ScanPlan.analysisActions(plan, remind: request.remind)
        flowMark("SCAN auswertung art=\(request.kind.rawValue) "
                 + "schritte=\(actions.map(\.stepKind.rawValue).joined(separator: "+"))")
        let analysis = RoutedSend(text: text, plan: SendPlan(actions: actions), turn: turn,
                                  history: freshHistory, attachments: [], files: [],
                                  convID: convID, started: Date())
        for (index, action) in actions.enumerated() {
            await perform(action, in: analysis, slot: slot, number: number + index)
        }
        guard !Task.isCancelled else { return }
        let updatedMessages = store.conversations.first(where: { $0.id == convID })?.messages ?? []
        guard updatedMessages.count > priorCount,
              let answerID = updatedMessages[priorCount...].last(where: { $0.role == .assistant })?.id else {
            return
        }
        store.attachScanRef(outcome.attachment, to: answerID, in: convID)
        guard request.remind else { return }
        let reminder = await ToolRouter.scanReminder(baseURL: settings.baseURL, key: settings.apiKey,
                                                     model: ask.model, text: text, context: context,
                                                     history: freshHistory, document: outcome.text,
                                                     catalog: ask.catalog,
                                                     eraseHistoryWord: settings.spokenDeleteHistory,
                                                     thinking: ask.thinking)
        guard !Task.isCancelled else { return }
        guard case .reminder(let plan) = reminder?.route,
              let offer = ScanReminderOffer(from: plan) else {
            flowMark("SCAN erinnerung nicht angeboten")
            return
        }
        store.attachReminderOffer(offer, to: answerID, in: convID)
    }

    @MainActor func createScanReminder(_ offer: ScanReminderOffer, messageID: UUID) async {
        guard !Task.isCancelled else { return }
        guard let request = offer.request, let convID = store.currentID,
              store.current?.messages.contains(where: { $0.id == messageID }) == true else { return }
        await runExclusiveBusy {
            let runner = reminderDesk.runner()
            let outcome = await busy.running(L.t("rem_working")) {
                await runner.run(request)
            }
            guard !Task.isCancelled else { return }
            flowMarkPersonal("SCAN erinnerung per taste titel=\(offer.title) erfolg=\(outcome.ref != nil) "
                             + "\(outcome.trace)")
            guard outcome.ref != nil else {
                appendFailure(outcome.text, model: settings.chatModel, convID: convID, started: Date())
                return
            }
            store.settleReminderOffer(outcome.ref, to: messageID, in: convID)
            announceAnswer(outcome.text)
        }
    }

}
