@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func startSend() {
        guard runTask == nil else { return }
        runGeneration += 1
        let generation = runGeneration
        runTask = Task { @MainActor in
            await send()
            if generation == runGeneration { runTask = nil }
        }
    }

    @MainActor func sendNow() async {
        guard runTask == nil else { return }
        runGeneration += 1
        let generation = runGeneration
        let task = Task { @MainActor in await send() }
        runTask = task
        await task.value
        if generation == runGeneration { runTask = nil }
    }

    @MainActor func stopRun() {
        flowMark("ABBRUCH taste laufend=\(runTask != nil) busy=\(busy.isBusy) stream=\(isStreaming) "
                 + "kette=\(chainRun.isRunning) voice=\(voiceBusy)")
        stopRunningAnswer()
        runTask = nil
        if voiceBusy, !settings.voice.conversationMode { abortVoice() }
        listenNotice.show(L.t("run_stopped"))
    }

    @MainActor func cancelLiveWork() {
        chainRun.requestStop()
        runTask?.cancel()
        ChatRunner.shared.cancelAll()
    }

    @MainActor func stopRunningAnswer() {
        cancelLiveWork()
        runGeneration += 1
        speechInterrupted = true
        speech.stop()
    }

    @MainActor func send() async {
        flowMark("SEND enter pending=\(pendingImages.count) dateien=\(pendingFiles.count) chars=\(input.count)")
        speechInterrupted = false
        speech.stop()
        guard !isBusy, !isStreaming else {
            flowMark("SEND blocked busy=\(isBusy) streaming=\(isStreaming)")
            return
        }
        guard !pendingFiles.contains(where: { $0.reading }) else {
            flowMark("SEND blocked datei_liest=\(pendingFiles.count)")
            return
        }
        guard !pendingFiles.contains(where: { $0.failed }) else {
            let name = pendingFiles.first(where: { $0.failed })?.name ?? ""
            flowMark("SEND blocked datei_unlesbar=\(name)")
            queueAlert(L.FriendlyError(message: L.fmt("file_unreadable", name), detail: "",
                                       openSettings: false))
            return
        }
        AppSettings.flushKeySave()
        guard settings.isConfigured else { showSettings = true; return }
        guard pendingImages.isEmpty || settings.hasVisionModel else {
            flowMark("SEND blockiert ohne vision-modell bilder=\(pendingImages.count)")
            queueAlert(L.FriendlyError(message: L.t("vision_model_needed"), detail: "",
                                       openSettings: true))
            return
        }
        let hasVideo = pendingFiles.contains { $0.kind == .video }
        guard !hasVideo || settings.hasVideoModel else {
            flowMark("SEND blockiert ohne video-modell videos=1")
            queueAlert(L.FriendlyError(message: L.t("video_model_needed"), detail: "",
                                       openSettings: true))
            return
        }
        isBusy = true
        defer { isBusy = false }

        let draft = input
        let text = draft.trimmed
        let imgs = pendingImages
        let docs = pendingFiles
        input = ""
        pendingImages = []
        pendingFiles = []

        guard let routed = await withBusy(L.t("processing"), { await self.route(text: text, pictures: imgs, files: docs) }) else {
            restoreDraft(draft, pictures: imgs, files: docs)
            return
        }
        guard !Task.isCancelled else {
            flowMark("ABBRUCH phase=routing")
            let appended = store.conversations.first { $0.id == routed.convID }?
                .messages.contains { $0.id == routed.history.last?.id && $0.role == .user } ?? false
            if !appended { restoreDraft(draft, pictures: imgs, files: docs) }
            return
        }
        #if DEBUG
        probeLastPlan = routed.plan
        #endif
        await run(routed)
    }

    @MainActor func route(text: String, pictures imgs: [PendingPicture],
                                  files docs: [PendingFile]) async -> RoutedSend? {
        if store.current == nil { store.newConversation() }
        guard let convID = store.current?.id else { return nil }

        let media = store.media
        let written = LockedValue<[String]>([])
        guard let prepared = await Offload.orNil({ () -> [(Attachment, Data)] in
            var out: [(Attachment, Data)] = []
            for item in imgs {
                let t0 = ContinuousClock.now
                let existing = item.file
                guard let name = existing ?? media.store(item.image) else { continue }
                guard let data = media.data(for: Attachment(file: name)) else {
                    if existing == nil { media.discardStored([name]) }
                    continue
                }
                if existing == nil { written.mutate { $0.append(name) } }
                flowLog.info("PREP file=\(name, privacy: .public) ms=\(msOf(t0.duration(to: .now)))")
                out.append((Attachment(file: name), data))
            }
            return out
        }) else {
            let names = written.current
            if !names.isEmpty { media.discardStored(names) }
            return nil
        }
        flowMark("SEND prepared n=\(prepared.count)")

        let attachments = prepared.map(\.0)
        let attached = docs.map(\.attached)
        let ocrFiles: [OcrFile]? = imgs.contains(where: { $0.ocrFile != nil })
            ? imgs.compactMap { $0.ocrFile } : nil
        let message = ChatMessage(role: .user, text: text, images: attachments,
                                  files: attached, ocrFiles: ocrFiles)
        let prior = store.conversations.first { $0.id == convID }?.messages ?? []
        let history = prior + [message]
        let loaded = Dictionary(prepared.map { ($0.0.file, $0.1) }, uniquingKeysWith: { first, _ in first })
        let documents = store.documents
        guard let turn = await Offload.orNil({
            ConversationMemory.turn(from: history, load: { loaded[$0.file] ?? media.data(for: $0) },
                                    fileText: { documents.text(named: $0) },
                                    videoData: { documents.data(named: $0) })
        }) else {
            let names = written.current
            if !names.isEmpty { media.discardStored(names) }
            return nil
        }
        guard !turn.needsVideo || settings.hasVideoModel else {
            let names = written.current
            if !names.isEmpty { media.discardStored(names) }
            queueAlert(L.FriendlyError(message: L.t("video_model_needed"), detail: "",
                                       openSettings: true))
            return nil
        }
        guard store.appendMessage(message, to: convID) else {
            let names = written.current
            if !names.isEmpty { media.discardStored(names) }
            return nil
        }
        let started = Date()
        let context = SendContext(attachedImage: !attachments.isEmpty,
                                  rememberedImage: attachments.isEmpty && turn.needsVision,
                                  attachedVideo: turn.needsVideo,
                                  attachedFile: attached.contains { $0.kind != .video })
        let pictureOnly = ToolRouter.carriesOnlyPictures(text: text, pictures: attachments.count)
        let plan: SendPlan
        if pictureOnly {
            plan = SendPlan.singleChat
        } else {
            plan = await ToolRouter.plan(routerAsk(text, context: context, history: history,
                                                   needsVision: turn.needsVision, picture: turn.images.last,
                                                   extraPictures: Array(turn.images.dropLast()),
                                                   model: settings.answeringModel(hasPictures: turn.needsVision,
                                                                                  hasVideo: turn.needsVideo)))
        }
        flowMarkPersonal("SEND attached=\(attachments.count) remembered=\(turn.images.count) "
                 + "dateien=\(attached.count) "
                 + "router=\(pictureOnly ? "übersprungen" : "gefragt") "
                 + "werkzeug=\(String(describing: plan.primary.route)) kette=\(plan.traceLine) "
                 + Self.sendTrace(decision: plan.primary))
        return RoutedSend(text: text, plan: plan, turn: turn, history: history,
                          attachments: attachments, files: attached,
                          convID: convID, started: started,
                          freshPictureFiles: attachments.map(\.file))
    }

    @MainActor func routerAsk(_ text: String, context: SendContext, history: [ChatMessage], needsVision: Bool,
                              picture: Data? = nil, extraPictures: [Data] = [],
                              document: String = "", model: String? = nil) async -> RouterAsk {
        let model = model ?? settings.answeringModel(hasPictures: needsVision)
        let compact = settings.provider == .local
        var catalog = ""
        if !compact, settings.memory.enabled { catalog = await store.memory.catalog() }
        var watchCatalog = ""
        if !compact { watchCatalog = await store.watches.catalog() }
        let reminderLists = await reminderDesk.store.lists()
        return RouterAsk(baseURL: settings.baseURL, key: settings.apiKey, model: model, text: text,
                         context: context, history: RouterHistory.forRouting(history, compact: compact),
                         picture: picture, extraPictures: extraPictures, catalog: catalog,
                         eraseHistoryWord: settings.spokenDeleteHistory,
                         document: document, thinking: settings.thinkingOffDirective(for: model),
                         watchCatalog: watchCatalog, compact: compact,
                         reminderLists: reminderLists,
                         reminderPlaceExists: { @MainActor name in
                             await reminderDesk.places.locate(name) != nil
                         },
                         videoGenerationAvailable: settings.hasVideoGenerationModel)
    }

    @MainActor private func restoreDraft(_ draft: String, pictures: [PendingPicture],
                                         files: [PendingFile]) {
        if input.isEmpty { input = draft }
        if pendingImages.isEmpty { pendingImages = pictures }
        if pendingFiles.isEmpty { pendingFiles = files }
    }

    @MainActor func readProduct(in pictures: [Data], question: String) async -> ProductFinding? {
        guard let picture = pictures.last else { return nil }
        let model = settings.answeringModel(hasPictures: true)
        let baseURL = settings.baseURL
        let key = settings.apiKey
        let scan = productScanner
        let thinking = settings.thinkingOffDirective(for: model)
        return await withBusy(L.t("product_reading")) {
            let found = try? await scan.scan(baseURL: baseURL, key: key, model: model, question: question,
                                             image: picture, thinking: thinking)
            flowMarkPersonal("PRODUKTbefund bilder=\(pictures.count) model=\(model) "
                             + "ergebnis=\(found?.traceLine ?? "keins")")
            return found
        }
    }

    @MainActor func run(_ routed: RoutedSend) async {
        guard !Task.isCancelled else { return }
        let actions = routed.plan.actions
        guard actions.count > 1 else {
            await perform(routed.plan.primary, in: routed, slot: nil)
            return
        }
        let stages = ChainSchedule.stages(actions, limit: chainParallelSteps)
        flowMark("KETTE schritte=\(actions.count) \(routed.plan.traceLine) "
                 + "eine_antwort=\(routed.plan.merges) "
                 + "stufen=\(stages.map { String($0.count) }.joined(separator: "+"))")
        for (index, action) in actions.enumerated() {
            flowMark("KETTE stufe=\(index + 1) schlussel=\(action.stepKey)"
                     + (ChainSchedule.runsConcurrently(action) ? " nebenlaeufig=ja" : ""))
        }
        let merges = routed.plan.merges
        let writer = ChainMessageWriter()
        chainRun.begin()
        defer { chainRun.end() }
        var step = routed
        var convID = routed.convID
        var consumed = 0
        var reached = 0
        for stage in stages {
            guard !Task.isCancelled, chainRun.mayRun(step: reached + 1) else {
                writer.close(upTo: actions.count)
                reportStop(skipped: actions.count - reached, in: routed)
                return
            }
            step = await step.continuing(with: writer.carry, since: consumed, media: store.media)
            consumed = writer.carry.pieces.count
            step.convID = convID
            reached += stage.count
            let snapshot = step
            let job = ChainStageJob(view: self, step: snapshot, actions: actions, writer: writer,
                                    merges: merges, stage: stage)
            await job.runConcurrently()
            let deletesHistory = stage.contains { index in
                if case .history = actions[index].route { return true } else { return false }
            }
            if deletesHistory, let current = store.currentID {
                convID = current
                step.convID = current
            }
        }
        if merges { writer.speakNext { announceAnswer($0) } }
    }

    var chainParallelSteps: Int {
        settings.provider == .local ? 1 : ChainSchedule.inFlight
    }

    @MainActor func reportStop(skipped: Int, in routed: RoutedSend) {
        flowMark("KETTE angehalten übersprungen=\(skipped)")
        store.appendAssistant(L.fmt("chain_stopped", String(skipped)), model: nil,
                              elapsed: Date().timeIntervalSince(routed.started),
                              to: store.currentID ?? routed.convID)
    }

    @MainActor func turnWithFoundPicture(for turn: ModelTurn) async -> ModelTurn {
        guard turn.images.isEmpty else { return turn }
        guard let messages = store.current?.messages,
              let asked = messages.lastIndex(where: { $0.role == .user }) else { return turn }
        guard let gallery = messages[asked...].reversed().compactMap(\.gallery).first,
              let file = gallery.pictures.first?.file else { return turn }
        let media = store.media
        guard let data = await Offload.orNilFlat({ media.data(named: file) }) else { return turn }
        flowMarkPersonal("BILDSTUFE nimmt erstes Fundstück datei=\(file)")
        return turn.continuing(after: "", pictures: [data], files: [file])
    }

    @MainActor func perform(_ decision: ToolDecision, in routed: RoutedSend, slot: AnswerSlot?,
                                    number: Int = 1) async {
        guard !Task.isCancelled else { return }
        let text = routed.text
        let turn = routed.turn
        let history = routed.history
        let convID = routed.convID
        let started = routed.started
        let focus = WishRouting.answerFocus(decision, among: routed.plan.actions)
        switch decision.route {
        case .priceWatch(let request):
            await runPriceWatchFlow(request, question: decision.ownWords(or: text), convID: convID,
                                    started: started, slot: slot)
        case .dayBriefing(let request):
            await runDayBriefingFlow(request, convID: convID, started: started, slot: slot)
        case .imageEdit:
            let editTurn = await turnWithFoundPicture(for: turn)
            await runImageFlow(prompt: decision.pictureText(decision.pictureInstructionText, message: text),
                               history: history, turn: editTurn,
                               fresh: routed.freshPictureFiles,
                               isEdit: true, convID: convID, started: started,
                               monochrome: decision.pictureMonochrome, slot: slot)
        case .scanDocument(let request):
            await runScanFlow(request, text: decision.ownWords(or: text), convID: convID,
                              started: started, slot: slot, number: number)
        case .imageCreate:
            await runImageFlow(prompt: decision.pictureText(decision.picturePromptText, message: text),
                               history: history,
                               turn: turn.withoutPictures(), fresh: [],
                               isEdit: false, convID: convID, started: started,
                               composeFromChat: decision.picturePrompt == nil, slot: slot)
        case .videoCreate(let request):
            await runVideoFlow(request, sourceVideo: turn.videos.last,
                               sourceFile: turn.videoFiles.last, convID: convID,
                               started: started, slot: slot)
        case .translate(let job):
            await runTranslationFlow(job, convID: convID, started: started, slot: slot)
        case .calendar:
            await runCalendarFlow(turn: turn, text: decision.ownWords(or: text), history: history, convID: convID,
                                  started: started, plan: decision.calendarPlan, focus: focus, slot: slot,
                                  number: number)
        case .reminder(let request):
            await runReminderFlow(request, convID: convID, started: started, slot: slot)
        case .timer(let request):
            await runTimerFlow(request, convID: convID, started: started, slot: slot)
        case .readAloud(let request):
            await runReadAloudFlow(request, convID: convID, started: started, slot: slot)
        case .readAnswer:
            speakLastAnswer(convID: convID, started: started, slot: slot)
        case .nearbyPlace(let terms, let mode):
            await runPlaceFlow(.nearby, terms: terms, wish: decision.ownWords(or: text), mode: mode,
                               convID: convID, started: started, slot: slot)
        case .routeToPlace(let terms, let mode):
            await runPlaceFlow(.route, terms: terms, wish: decision.ownWords(or: text), mode: mode,
                               convID: convID, started: started, slot: slot)
        case .priceSearch(let terms, let country, let nearby):
            await runPriceSearch(terms: terms, country: country, nearby: nearby,
                                 question: decision.ownWords(or: text),
                                 pictures: routed.attachedPictures, history: history,
                                 convID: convID, started: started, slot: slot)
        case .call(let request):
            await runCallFlow(request, convID: convID, started: started, slot: slot)
        case .clock(let request):
            tellTime(request, convID: convID, started: started, slot: slot)
        case .music(let request):
            await runMusicFlow(request, convID: convID, started: started, slot: slot)
        case .message(let request):
            await runMessageFlow(request, convID: convID, started: started, slot: slot)
        case .memory(let request):
            if request.action == .suggest, !settings.memory.offersSuggestions {
                guard slot == nil else { return }
                await streamChat(turn: turn, history: history, convID: convID, started: started, query: text)
            } else {
                await runMemoryFlow(request, convID: convID, started: started, slot: slot)
            }
        case .history:
            await runHistoryFlow(convID: convID, started: started, slot: slot)
        case .appStatus:
            await runAppStatusFlow(convID: convID, started: started, slot: slot)
        case .weather(let request):
            await runWeatherFlow(request, convID: convID, started: started, slot: slot)
        case .code(let language):
            await streamChat(turn: turn, history: history, convID: convID, started: started,
                             system: SystemPrompt.code(language: language), question: decision.ownWords(or: text),
                             focus: focus, slot: slot)
        case .pictureSearch(let query):
            await runPictureSearch(query: query, images: turn.images,
                                   convID: convID, started: started, history: history, slot: slot)
        case .chat:
            if let query = decision.searchQuery {
                await runWebSearch(query: query, question: decision.ownWords(or: text), images: turn.images,
                                   convID: convID, started: started, history: history,
                                   slot: slot, detailWish: decision.detailWish)
            } else {
                await streamChat(turn: turn, history: history, convID: convID, started: started,
                                 question: decision.ownWords(or: text), focus: focus,
                                 query: text, memoryKeys: decision.memoryKeys, slot: slot)
            }
        }
    }

}

@MainActor
final class ChainStageJob {
    private let view: ChatView
    private let step: RoutedSend
    private let actions: [ToolDecision]
    private let writer: ChainMessageWriter
    private let merges: Bool
    private let stage: [Int]

    init(view: ChatView, step: RoutedSend, actions: [ToolDecision], writer: ChainMessageWriter,
         merges: Bool, stage: [Int]) {
        self.view = view
        self.step = step
        self.actions = actions
        self.writer = writer
        self.merges = merges
        self.stage = stage
    }

    nonisolated func runConcurrently() async {
        let stage = self.stage
        let jobs = stage.enumerated().map { offset, index in
            Task { @MainActor in await self.run(index, offset: offset) }
        }
        await withTaskCancellationHandler {
            for job in jobs { await job.value }
            flowMark("KETTE stufe fertig schritte=\(stage.count) abbruch=\(Task.isCancelled)")
        } onCancel: {
            flowMark("KETTE stufe abbruch schritte=\(stage.count)")
            for job in jobs { job.cancel() }
        }
    }

    private func run(_ index: Int, offset: Int) async {
        if offset > 0, ChainSchedule.stagger > .zero {
            try? await Task.sleep(for: ChainSchedule.stagger * offset)
        }
        flowMark("KETTE schritt start schritt=\(index) abbruch=\(Task.isCancelled)")
        await view.perform(actions[index], in: step,
                           slot: AnswerSlot(writer: writer, writes: merges, step: index),
                           number: index + 1)
        flowMark("KETTE schritt ende schritt=\(index) abbruch=\(Task.isCancelled)")
        writer.finish(step: index)
    }
}
