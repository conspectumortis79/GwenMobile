import GwenMobileKit
import SwiftUI
import UIKit

extension ChatView {
    var scaffold: some View {
        scaffoldLifecycle
    }

    private var scaffoldLayout: some View {
        VStack(spacing: 0) {
            ChatHeaderView(showHistory: $showHistory,
                           showSettings: $showSettings,
                           onNewChat: { store.newConversation() },
                           onToggleListen: { toggleListenMode() },
                           onToggleConversation: { toggleConversationMode() },
                           onCancelGallery: { cancelGallerySelection() },
                           onOpenHelp: { HelpRequests.shared.ask() })
            ChatThreadView(autoScroll: autoScroll, busy: busy, voice: voice,
                           routeDesk: routeDesk, gallerySelection: gallerySelection,
                           sourceChecks: sourceChecks, isStreaming: isStreaming,
                           streamText: streamText, webStatus: webStatus,
                           inputFocused: $inputFocused,
                           actionsFor: { rowActions(in: $0) },
                           onScrollProxy: { proxy in
                               #if DEBUG
                               ProbeHook.attachScrollProxy?(self, proxy)
                               #else
                               _ = proxy
                               #endif
                           },
                           onPlaceCall: { number in Task { await placeCall(number) } },
                           onDropFiles: { acceptDroppedFiles($0) })
                .overlay(alignment: .bottom) { galleryBar }
                .overlay(alignment: .bottom) {
                    ChatNoticeOverlay(notice: listenNotice)
                        .animation(.easeInOut(duration: 0.2), value: listenNotice.text)
                }
                .animation(.easeInOut(duration: 0.15), value: showsGalleryBar)
            Divider()
            UndoBarHost(cleaner: store.cleaner)
            ChatInputBar(voice: voice, busy: busy, speech: speech, isStreaming: isStreaming,
                         isBusy: isBusy, isRunning: runTask != nil, chainIsRunning: chainRun.isRunning,
                         conversationMode: settings.voice.conversationMode,
                         input: $input, attachMenu: $attachMenu,
                         pendingImages: $pendingImages, pendingFiles: $pendingFiles,
                         inputFocused: $inputFocused,
                         onStartSend: { startSend() },
                         onStopRun: { stopRun() },
                         onToggleVoice: { toggleVoice() },
                         onRemovePendingFile: { file in removePendingFile(file) })
        }
        .background(Color(.systemBackground))
        .overlay {
            if listenGlowPhase != .hidden {
                ListeningGlowOverlay(phase: listenGlowPhase)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: listenGlowPhase != .hidden)
        .environmentObject(store.images)
        .environmentObject(gallerySelection)
        .environmentObject(galleryOperation)
        .id(settings.language)
        .environment(\.locale, settings.language.locale)
    }

    private var scaffoldPresentations: some View {
        scaffoldLayout
        .sheet(isPresented: $showSettings, onDismiss: {
            settingsCategory = nil
        }) {
            SettingsView(initialCategory: settingsCategory)
                .environmentObject(store)
                .environmentObject(store.cleaner)
        }
        .sheet(isPresented: $showHelp) {
            HelpCenterView(onUseExample: { text in
                input = text
                inputFocused = true
            })
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(store)
                .environmentObject(store.cleaner)
        }
        .sheet(isPresented: $showBriefingOpen) {
            DayBriefingNotificationView(day: briefingOpenDay)
        }
        .fullScreenCover(item: $imagePreview) { target in
            ImageViewerView(target: target, reader: store.media)
        }
        .sheet(item: $calendarEvent) { ref in
            CalendarEventView(ref: ref) { calendarEvent = nil }
        }
        .sheet(isPresented: Binding(
            get: { sourceReportSheet != nil },
            set: { if !$0 { sourceReportSheet = nil } }
        )) {
            if let report = sourceReportSheet {
                SourceReportView(report: report)
            }
        }
        .alert(L.t("error"), isPresented: Binding(
            get: { !alerts.isEmpty },
            set: { showing in if !showing { dismissAlert() } }
        )) {
            Button(L.t("ok"), role: .cancel, action: TapProbe.action({}))
            if currentAlert?.openSettings == true {
                Button(L.t("open_settings"), action: TapProbe.action({
                    showSettings = true
                }))
            }
            Button(L.t("help_title"), action: TapProbe.action({
                HelpRequests.shared.ask()
            }))
        } message: {
            Text(verbatim: alertText)
                .scaledFont(13)
        }
    }

    private var scaffoldOverlays: some View {
        scaffoldPresentations
        .onChange(of: voice.lastError) { _, _ in syncPendingAlerts() }
        .onChange(of: store.storageProblem) { _, _ in syncPendingAlerts() }
        .overlay {
            if attachMenu {
                ZStack(alignment: .bottomLeading) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                        .onTapGesture(perform: TapProbe.action({
                            withAnimation(.easeInOut(duration: 0.15)) { attachMenu = false }
                        }))
                    ChatAttachMenuCard(attachMenu: $attachMenu, pendingItems: $pendingItems,
                                       onMenuScan: { Task { await startMenuScan() } },
                                       onOpenFilePicker: { openFilePicker() },
                                       onOpenVideoPicker: { openVideoPicker() },
                                       onPicked: { runOCR(on: queue(pictures: $0)) })
                        .padding(.leading, 10)
                        .padding(.bottom, 62)
                }
                .transition(.opacity)
            }
        }
    }

    private var scaffoldLifecycle: some View {
        scaffoldOverlays
        .onAppear { scaffoldAppear() }
        .onChange(of: listenToken?.wrappedValue ?? 0) { _, _ in
            takeListenRequest(from: "url")
        }
        .onChange(of: briefingOpens.token) { _, _ in
            takeBriefingOpenRequest()
        }
        .onChange(of: helpOpens.token) { _, _ in
            takeHelpRequest()
        }
        #if DEBUG
        .onChange(of: testToken?.wrappedValue ?? 0) { _, _ in
            ProbeHook.start?(self)
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                AppSettings.flushKeySave()
                Task { await store.flushPendingSave() }
            }
            if phase == .active {
                settings.reloadBlockedKeys()
                pruneMemory()
                Task { await checkMemoryDue() }
                Task { await checkPriceWatches() }
                Task { await DayBriefingNotifier.refresh() }
                refreshVoiceAfterEngineChange()
            }
            syncListenPresence()
        }
        .onChange(of: settings.memory.retention) { _, fresh in
            Task { await store.memory.prune(retention: fresh) }
        }
        .onChange(of: settings.voice.conversationMode) { _, on in
            guard !on, !settings.voice.listenMode else { return }
            voice.cancel()
            Task { await releaseVoiceProcessingIfIdle() }
        }
        .onChange(of: settings.voice.listenMode) { _, on in
            guard !on, !settings.voice.conversationMode else { return }
            Task { await releaseVoiceProcessingIfIdle() }
        }
        .confirmationDialog(pendingSuggestions.count > 1 ? L.t("memory_suggest_title_many")
                            : L.t("memory_suggest_title"), isPresented: Binding(
            get: { !pendingSuggestions.isEmpty },
            set: { showing in if !showing { dismissPendingSuggestions() } }
        ), titleVisibility: .visible) {
            Button(L.t("memory_suggest_save"), action: TapProbe.action({ savePendingSuggestions() }))
            Button(L.t("memory_suggest_dismiss"), role: .cancel,
                   action: TapProbe.action({ dismissPendingSuggestions() }))
        } message: {
            Text(verbatim: pendingSuggestions.map(\.text).joined(separator: "\n\n"))
        }
        .onChange(of: listenGate) { _, gate in
            followListenGate(gate)
            syncListenPresence()
        }
        .onChange(of: voice.state) { _, _ in
            followListenGate(listenGate)
            syncListenPresence()
        }
        .onChange(of: showHelp) { _, _ in
            followListenGate(listenGate)
            syncListenPresence()
        }
        .onChange(of: microphone.engineRecoveries) { _, _ in refreshVoiceAfterEngineChange() }
        .onDisappear { CameraPresenter.shared.onImage = nil; DocumentPresenter.shared.onURLs = nil }
    }

    @MainActor private func scaffoldAppear() {
        flowMark("CHAT appear listenToken=\(listenToken?.wrappedValue ?? -1) voice=\(voice.state)")
        syncPendingAlerts()
        installWakeGreeting()
        if settings.isConfigured, settings.profile.needsListing {
            Task { try? await settings.reloadModels() }
        } else if settings.isConfigured, !settings.modelsNeedingCaps.isEmpty {
            let textModels = ModelFilter.textCandidates(settings.availableModels)
            Task { await settings.refreshModelCaps(for: textModels) }
        }
        CameraPresenter.shared.onImage = { img in
            flowMark("CAMERA image size=\(Int(img.size.width))x\(Int(img.size.height))")
            let item = PendingPicture(image: img, file: nil)
            runOCR(on: queue(pictures: [item]))
        }
        DocumentPresenter.shared.onURLs = { urls in importPicked(urls) }
        takeListenRequest(from: "appear")
        takeBriefingOpenRequest()
        takeHelpRequest()
        followListenGate(listenGate)
        syncListenPresence()
        if settings.voice.onlyMyVoice {
            Task { _ = await SpeakerEmbedder.shared.ensureUsable() }
        }
        pruneMemory()
        Task { await checkMemoryDue() }
        Task { await checkPriceWatches() }
        Task { await DayBriefingNotifier.refresh() }
        #if DEBUG
        ProbeHook.appear?(self)
        ProbeHook.installTouchLog?()
        if let name = ProbeHook.launchName() { ProbeHook.dispatch?(self, name) }
        #endif
        MainLoopMonitor.start()
    }

    @MainActor func takeHelpRequest() {
        guard helpOpens.token > handledHelp else { return }
        handledHelp = helpOpens.token
        if !showHelp {
            showHelp = true
        }
    }

    func rowActions(in conversation: UUID) -> ChatThreadRowActions {
        ChatThreadRowActions(
            onEdit: { att in attachForEditing(att) },
            onPreview: { message, att in
                imagePreview = ImagePreviewTarget(tappedFile: att.file, files: message.imageFiles)
            },
            onDelete: { id in Task { await store.cleaner.deleteMessage(id, in: conversation) } },
            onRoute: { place in openRoute(to: place) },
            onCall: { number in Task { await placeCall(number) } },
            onOpenEvent: { ref in calendarEvent = ref },
            onOpenPicture: { message, picture in
                imagePreview = ImagePreviewTarget(tappedFile: picture.file, files: message.storedImageFiles)
            },
            onMorePictures: { message in Task { await morePictures(message) } },
            onWeatherDay: { id, date in Task { await switchWeatherDay(message: id, date: date) } },
            onWeatherSpeak: { id in speakWeather(message: id) },
            onBriefingDay: { id, day in Task { await switchBriefingDay(message: id, day: day) } },
            onBriefingSpeak: { id in speakBriefing(message: id) },
            onBriefingNotify: { id in notifyBriefing(message: id) },
            onReminderOffer: { id, offer in Task { await createScanReminder(offer, messageID: id) } },
            onOpenSourceReport: { report in sourceReportSheet = report }
        )
    }
}
