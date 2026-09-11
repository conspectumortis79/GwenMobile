import SwiftUI
import PhotosUI
import UIKit

@MainActor
struct ChatView: View {
    @EnvironmentObject var store: ChatStore
    @ObservedObject var settings = AppSettings.shared
    var listenToken: Binding<Int>? = nil
    var testToken: Binding<Int>? = nil
    var testCmd: String = ""
    @State private var scrolledAnchor: AnyHashable?
    @State private var lastScrollDate = Date.distantPast
    @State private var attachMenu = false
    @State var input: String = ""
    @State private var pendingItems: [PhotosPickerItem] = []
    @State var pendingImages: [(image: UIImage, file: String?)] = []
    @State private var isStreaming = false
    @State private var isBusy = false
    @State private var streamText: String = ""
    @State private var alertError: L.FriendlyError?
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var imageWorking = false
    @State private var workingIsEdit = false
    @State private var workingLabelOverride: String? = nil
    @State private var webStatus: String? = nil
    @FocusState var inputFocused: Bool

    #if DEBUG
    @State var scrollProxy: ScrollViewProxy?
    @State var testRunning = false
    #endif

    private var imageWorkingLabel: String {
        workingLabelOverride ?? (workingIsEdit ? L.t("editing_image") : L.t("generating_image"))
    }
    @StateObject private var voice = VoiceTranscriber()
    @StateObject private var speech = SpeechSynthesizer()

    var body: some View {
        #if DEBUG
        let _ = RenderStats.chatBody.bump()
        #endif
        VStack(spacing: 0) {
            header
            thread
            Divider()
            UndoBarHost(cleaner: store.cleaner)
            inputBar
        }
        .background(Color(.systemBackground))
        .environmentObject(store.images)
        .id(settings.language)
        .environment(\.locale, settings.language.locale)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
                .environmentObject(store.cleaner)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(store)
                .environmentObject(store.cleaner)
        }
        .alert(L.t("error"), isPresented: Binding(
            get: { alertError != nil || voice.lastError != nil },
            set: { if !$0 { alertError = nil; voice.lastError = nil } }
        )) {
            Button(L.t("ok"), role: .cancel) { alertError = nil; voice.lastError = nil }
            if (alertError ?? voice.lastError)?.openSettings == true {
                Button(L.t("open_settings")) {
                    alertError = nil; voice.lastError = nil; showSettings = true
                }
            }
        } message: {
            let e = alertError ?? voice.lastError
            Text((e?.message ?? "") + (e?.detail.isEmpty == false ? "\n\n\(e!.detail)" : ""))
                .font(.system(size: 13))
        }
        .overlay {
            if attachMenu {
                ZStack(alignment: .bottomLeading) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) { attachMenu = false }
                        }
                    attachMenuCard
                        .padding(.leading, 10)
                        .padding(.bottom, 62)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            store.cleaner.discardPendingDeletion()
            CameraPresenter.shared.onImage = { img in
                flowMark("CAMERA image size=\(Int(img.size.width))x\(Int(img.size.height))")
                pendingImages = [(image: img, file: nil)]
            }
            if (listenToken?.wrappedValue ?? 0) > 0 { startListeningFromShortcut() }
            #if DEBUG
            if let name = DebugLaunchTrigger.flowTestName() { dispatchFlowTest(name) }
            #endif
            MainLoopMonitor.start()
        }
        .onChange(of: listenToken?.wrappedValue ?? 0) { _, _ in
            startListeningFromShortcut()
        }
        .onChange(of: testToken?.wrappedValue ?? 0) { _, _ in
            startFlowTest()
        }
    }

    func attachScrollProxy(_ proxy: ScrollViewProxy) {
        #if DEBUG
        scrollProxy = proxy
        #endif
    }

    func startFlowTest() {
        #if DEBUG
        dispatchFlowTest(testCmd)
        #endif
    }

    #if DEBUG
    func dispatchFlowTest(_ name: String) {
        guard !name.isEmpty, !testRunning else { return }
        testRunning = true
        flowMark("FLOWTEST dispatched cmd=\(name)")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            await runFlowTest(name)
            flowMark("FLOWTEST finished cmd=\(name)")
            testRunning = false
        }
    }
    #endif

    @MainActor private func startListeningFromShortcut() {
        guard voice.state == .idle, !isStreaming, !imageWorking else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard settings.isConfigured, voice.state == .idle else { return }
            inputFocused = false
            voice.start(baseURL: settings.baseURL, key: settings.apiKey,
                        model: settings.audioModel) { text in
                self.voiceDidTranscribe(text)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            HStack(spacing: 7) {
                Image("HeaderIcon")
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text("GwenMobile").font(.system(size: 17, weight: .bold))
                Spacer(minLength: 8)
                headerButton("square.and.pencil") { store.newConversation() }
                headerButton("list.bullet") { showHistory = true }
                headerButton("gearshape") { showSettings = true }
            }
            .frame(height: 36)
            .foregroundStyle(Color.primary)
            Text(store.current?.title ?? L.t("new_chat"))
                .font(.system(size: 13))
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(Color(.secondarySystemBackground))
        .overlay(Divider(), alignment: .bottom)
    }

    private func headerButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(.systemGray5)))
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
    }

    private var thread: some View {
        GeometryReader { geo in
            threadBody(threadWidth: geo.size.width - 24)
        }
    }

    private func threadBody(threadWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let conv = store.current {
                        if conv.messages.isEmpty && !isStreaming {
                            emptyHint
                        }
                        let rows = Self.makeRows(conv.messages)
                        let lastID = conv.messages.last?.id
                        ForEach(rows) { row in
                            switch row {
                            case .day(let date):
                                dayLabel(date)
                            case .msg(let msg):
                                Bubble(message: msg, media: store.media,
                                       time: Self.timeString(msg.date),
                                       isLast: msg.id == lastID && !isStreaming,
                                       width: threadWidth,
                                       onEdit: { att in attachForEditing(att) },
                                       onDelete: { id in store.cleaner.deleteMessage(id, in: conv.id) })
                                    .equatable()
                            }
                        }
                    }
                    if isStreaming {
                        Bubble(text: streamText, isUser: false, streaming: true)
                            .id("streaming")
                    }
                    if voice.state == .processing {
                        StatusBubble(text: L.t("asr_working")).id("asr_working")
                    }
                    if imageWorking {
                        StatusBubble(text: imageWorkingLabel).id("image_working")
                    }
                    if let webStatus {
                        WebStatusBubble(text: webStatus).id("web_status")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { attachScrollProxy(proxy) }
            .onAppear {
                if store.current?.messages.last != nil {
                    scrollToBottom(proxy)
                }
            }
            .onChange(of: store.currentID) { _, _ in
                scrolledAnchor = nil
                if store.current?.messages.last != nil {
                    scrollToBottom(proxy)
                }
            }
            .simultaneousGesture(TapGesture().onEnded { inputFocused = false })
            .onChange(of: streamText) { _, _ in scrollToBottom(proxy) }
            .onChange(of: isStreaming) { _, _ in scrollToBottom(proxy) }
            .onChange(of: voice.state) { _, s in
                if s == .processing { scrollToBottom(proxy) }
            }
            .onChange(of: imageWorking) { _, _ in scrollToBottom(proxy) }
            .onChange(of: workingLabelOverride) { _, _ in scrollToBottom(proxy) }
            .onChange(of: webStatus) { _, _ in scrollToBottom(proxy) }
            .onChange(of: store.current?.messages.count) { _, _ in scrollToBottom(proxy) }
        }
    }

    private var bottomAnchorID: AnyHashable? {
        if webStatus != nil { return "web_status" }
        if imageWorking { return "image_working" }
        if voice.state == .processing { return "asr_working" }
        if isStreaming { return "streaming" }
        return store.current?.messages.last?.id
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let target = bottomAnchorID else { return }
        let now = Date()
        if target == scrolledAnchor, now.timeIntervalSince(lastScrollDate) < Self.scrollMinInterval {
            return
        }
        scrolledAnchor = target
        lastScrollDate = now
        proxy.scrollTo(target, anchor: .bottom)
    }

    static let scrollMinInterval: TimeInterval = 0.2

    enum ThreadRow: Identifiable {
        case day(Date)
        case msg(ChatMessage)

        var id: String {
            switch self {
            case .day(let date): return "day-\(date.timeIntervalSince1970)"
            case .msg(let m): return "msg-\(m.id.uuidString)"
            }
        }
    }

    static func makeRows(_ msgs: [ChatMessage]) -> [ThreadRow] {
        var rows: [ThreadRow] = []
        rows.reserveCapacity(msgs.count * 2)
        let cal = Calendar.current
        for (idx, m) in msgs.enumerated() {
            if idx == 0 || !cal.isDate(m.date, inSameDayAs: msgs[idx - 1].date) {
                rows.append(.day(m.date))
            }
            rows.append(.msg(m))
        }
        return rows
    }

    private func dayLabel(_ date: Date) -> some View {
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(date) { day = L.t("today") }
        else if cal.isDateInYesterday(date) { day = L.t("yesterday") }
        else { day = Self.dayFormatter().string(from: date) }
        return Text(verbatim: "\(day) · \(Self.timeString( date))")
            .font(.system(size: 11))
            .foregroundStyle(Color(.tertiaryLabel))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
    }

    private var canSend: Bool {
        !isBusy && !isStreaming && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty)
    }

    func attachForEditing(_ att: Attachment) {
        let t0 = ContinuousClock.now
        guard let img = store.media.uiImage(for: att) else { return }
        flowMark("ATTACH_EDIT decode ms=\(msOf(t0.duration(to: .now))) size=\(Int(img.size.width))x\(Int(img.size.height))")
        pendingImages = [(image: img, file: att.file)]
        inputFocused = true
    }

    func lastImageCandidate() -> Attachment? {
        for msg in (store.current?.messages ?? []).reversed() {
            if msg.role == .assistant, let out = msg.outImages?.last { return out }
            if msg.role == .user {
                if let img = msg.images.last { return img }
                return nil
            }
        }
        return nil
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(L.t("empty_hint"))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if voice.state == .recording, let left = voice.remaining, left <= 10 {
                Text(L.n("asr_countdown", left))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(left <= 5 ? Color.red : Color(.secondaryLabel))
                    .transition(.opacity)
            }
            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { idx, item in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: item.image)
                                    .resizable().scaledToFill()
                                    .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                                Button { pendingImages.remove(at: idx) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .padding(3)
                            }
                        }
                    }.padding(.horizontal)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    if speech.isSpeaking {
                        speech.stop()
                    } else {
                        withAnimation(.easeInOut(duration: 0.15)) { attachMenu.toggle() }
                    }
                } label: {
                    Image(systemName: speech.isSpeaking ? "stop.fill" : "plus")
                        .font(.system(size: speech.isSpeaking ? 13 : 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(speech.isSpeaking ? Color.red : Color(.systemGray3)))
                }
                .accessibilityLabel(speech.isSpeaking ? L.t("read_aloud") : L.t("attach_photo"))

                TextField(L.t("message"), text: $input, axis: .vertical)
                    .font(.system(size: 17))
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(.systemBackground))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(.systemGray4), lineWidth: 0.7))
                    )

                Button { toggleVoice() } label: {
                    Image(systemName: voice.state == .recording ? "mic.fill"
                          : (voice.state == .processing ? "hourglass" : "mic"))
                        .font(.system(size: 19))
                        .foregroundStyle(voice.state == .recording ? Color.red : Color(.secondaryLabel))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(voice.state == .recording ? Color.red.opacity(0.12) : Color.clear))
                }
                .disabled(voice.state == .processing || isStreaming || imageWorking)

                Button {
                    if isStreaming {
                        ChatRunner.shared.cancel()
                    } else {
                        Task { await send() }
                    }
                } label: {
                    Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(canSend || isStreaming ? Color.blue : Color(.systemGray3)))
                }
                .disabled(!canSend && !isStreaming)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .animation(.easeInOut(duration: 0.15), value: speech.isSpeaking)
        }
        .background(Color(.secondarySystemBackground))
        .onChange(of: isStreaming) { _, v in if v { attachMenu = false } }
    }

    private var attachMenuCard: some View {
        let photoLbl = L.t("attach_photo")
        let camLbl = L.t("camera")
        let readLbl = L.t("read_aloud")
        let readState = settings.speakAnswers ? L.t("state_on") : L.t("state_off")
        return VStack(alignment: .leading, spacing: 6) {
            PhotosPicker(selection: $pendingItems, maxSelectionCount: 1, matching: .images) {
                menuRow("photo.on.rectangle.angled", photoLbl, state: nil, on: false)
            }
            .onChange(of: pendingItems) { _, items in
                if !items.isEmpty {
                    withAnimation(.easeInOut(duration: 0.15)) { attachMenu = false }
                }
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let img = await Task.detached(priority: .userInitiated, operation: {
                                MediaStore.thumbnail(data, maxPixel: ImagePolicy.uploadMaxPixel)
                            }).value
                            flowMark("PICKER decoded bytes=\(data.count) ok=\(img != nil)")
                            if let img { pendingImages = [(image: img, file: nil)] }
                        }
                    }
                    pendingItems = []
                }
            }
            Button { attachMenu = false; CameraPresenter.shared.present() } label: {
                menuRow("camera", camLbl, state: nil, on: false)
            }
            Divider().padding(.horizontal, 12)
            Button { settings.speakAnswers.toggle() } label: {
                menuRow(settings.speakAnswers ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        readLbl, state: readState, on: settings.speakAnswers)
            }
        }
        .buttonStyle(.plain)
        .padding(10)
        .frame(width: 290, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.22), radius: 14, y: 6))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private nonisolated func menuRow(_ symbol: String, _ label: String,
                                     state: String?, on: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Color(.secondaryLabel))
                .frame(width: 30)
            Text(label).font(.system(size: 17)).foregroundStyle(Color.primary)
            Spacer()
            if let state {
                Text(state).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(on ? Color.blue : Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 13).padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    @MainActor private func voiceDidTranscribe(_ text: String) {
        input = text
        Task { await send() }
    }

    private func toggleVoice() {
        guard settings.isConfigured else { showSettings = true; return }
        switch voice.state {
        case .idle:
            inputFocused = false
            voice.start(baseURL: settings.baseURL, key: settings.apiKey,
                        model: settings.audioModel) { text in
                self.voiceDidTranscribe(text)
            }
        case .recording:
            voice.stopAndTranscribe(baseURL: settings.baseURL, key: settings.apiKey,
                                    model: settings.audioModel) { text in
                self.voiceDidTranscribe(text)
            }
        case .processing:
            break
        }
    }

    @MainActor func send() async {
        flowMark("SEND enter pending=\(pendingImages.count) chars=\(input.count)")
        guard !isBusy, !isStreaming else {
            flowMark("SEND blocked busy=\(isBusy) streaming=\(isStreaming)")
            return
        }
        AppSettings.flushKeySave()
        guard settings.isConfigured else { showSettings = true; return }
        isBusy = true
        defer { isBusy = false }

        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let imgs = pendingImages
        input = ""
        pendingImages = []

        if store.current == nil { store.newConversation() }
        guard let convID = store.current?.id else { return }

        let media = store.media
        let prepared = await Task.detached(priority: .userInitiated) { () -> [(Attachment, Data)] in
            var out: [(Attachment, Data)] = []
            for item in imgs {
                let t0 = ContinuousClock.now
                guard let name = item.file ?? media.store(item.image),
                      let data = media.data(for: Attachment(file: name)) else { continue }
                flowLog.info("PREP file=\(name, privacy: .public) ms=\(msOf(t0.duration(to: .now)))")
                out.append((Attachment(file: name), data))
            }
            return out
        }.value
        flowMark("SEND prepared n=\(prepared.count)")

        let attachments = prepared.map(\.0)
        let attachedImages = prepared.map(\.1)
        let followUp = attachments.isEmpty && !text.isEmpty ? lastImageCandidate() : nil
        store.appendMessage(ChatMessage(role: .user, text: text, images: attachments), to: convID)
        let started = Date()

        var imagesForModel = attachedImages
        if imagesForModel.isEmpty, let followUp, let data = media.data(for: followUp) {
            imagesForModel = [data]
        }
        let hasImage = !imagesForModel.isEmpty
        let intent = hasImage && !text.isEmpty ? await detectIntent(for: text) : nil
        let history = store.conversations.first { $0.id == convID }?.messages ?? []

        switch SendRouter.route(text: text, hasImage: hasImage, intent: intent) {
        case .imageEdit:
            await runImageFlow(prompt: text, images: imagesForModel, isEdit: true,
                               convID: convID, started: started)
        case .imageCreate:
            await runImageFlow(prompt: text, images: [], isEdit: false,
                               convID: convID, started: started)
        case .calendar:
            await runCalendarFlow(text: text, history: history, convID: convID, started: started)
        case .chat:
            await streamChat(history: history, convID: convID, started: started)
        }
    }

    @MainActor private func detectIntent(for text: String) async -> ImageRoute? {
        let t0 = ContinuousClock.now
        flowMark("ROUTE detect begin")
        let route = await QwenAPI.detectImageIntent(baseURL: settings.baseURL,
                                                    key: settings.apiKey,
                                                    model: settings.chatModel,
                                                    instruction: text)
        flowMark("ROUTE detect done \(String(describing: route)) ms=\(msOf(t0.duration(to: .now)))")
        return route
    }

    @MainActor private func runImageFlow(prompt: String, images: [Data], isEdit: Bool,
                                        convID: UUID, started: Date) async {
        flowMark("IMAGEFLOW start edit=\(isEdit) images=\(images.count)")
        imageWorking = true
        workingIsEdit = isEdit
        defer { imageWorking = false }
        let baseURL = settings.baseURL
        let key = settings.apiKey
        let imageModel = settings.imageModel
        let text = prompt.isEmpty ? L.t("image_default_prompt") : prompt
        let media = store.media
        do {
            let req = try await Task.detached(priority: .userInitiated) {
                try QwenAPI.makeImageRequest(baseURL: baseURL, key: key,
                                             model: imageModel,
                                             prompt: text,
                                             inputImages: images,
                                             isEdit: isEdit)
            }.value
            let urls = try await QwenAPI.generateImage(req: req)
            flowMark("IMAGEFLOW generated urls=\(urls.count)")
            var outAtts: [Attachment] = []
            for u in urls {
                let data = try await QwenAPI.download(u)
                if let name = media.storeImageData(data) {
                    outAtts.append(Attachment(file: name))
                }
            }
            guard !outAtts.isEmpty else {
                alertError = L.FriendlyError(message: L.t("no_image"), detail: "", openSettings: false)
                return
            }
            let note = isEdit ? L.t("edit_done_note") : ""
            store.appendAssistant(note, model: imageModel,
                                  elapsed: Date().timeIntervalSince(started),
                                  to: convID, outImages: outAtts)
        } catch {
            store.appendAssistant(AnswerError.model(error.localizedDescription, model: imageModel, generic: L.t("err_generic")),
                                  model: imageModel,
                                  elapsed: Date().timeIntervalSince(started), to: convID)
        }
    }

    @MainActor private func runCalendarFlow(text: String, history: [ChatMessage],
                                            convID: UUID, started: Date) async {
        imageWorking = true
        workingLabelOverride = L.t("cal_working")
        defer { imageWorking = false; workingLabelOverride = nil }
        let chatModel = settings.chatModel
        do {
            let prior = Array(history.dropLast())
            if let plan = try await QwenAPI.calendarPlan(baseURL: settings.baseURL, key: settings.apiKey,
                                                         model: chatModel, instruction: text,
                                                         history: prior,
                                                         events: CalendarService.upcomingContext(),
                                                         calendars: CalendarService.calendarsContext()),
               plan.action != .none {
                let info = try await CalendarService.perform(plan)
                store.appendAssistant(info, model: chatModel,
                                      elapsed: Date().timeIntervalSince(started), to: convID)
            } else {
                await streamChat(history: history, convID: convID, started: started)
            }
        } catch {
            store.appendAssistant(AnswerError.other(error.localizedDescription, generic: L.t("err_cal_generic")), model: chatModel,
                                  elapsed: Date().timeIntervalSince(started), to: convID)
        }
    }

    @MainActor func streamChat(history: [ChatMessage], convID: UUID, started: Date) async {
        let model = history.contains(where: { !$0.images.isEmpty })
            ? settings.visionModel : settings.chatModel
        let rawWindow = Array(history.suffix(30))
        let lastImageIdx = rawWindow.lastIndex { $0.role == .user && !$0.images.isEmpty }
        let window = rawWindow.enumerated().map { idx, m -> ChatMessage in
            if idx == lastImageIdx || m.images.isEmpty { return m }
            var copy = m
            copy.images = []
            return copy
        }
        let windowImages = window.flatMap(\.images)
        let baseURL = settings.baseURL
        let key = settings.apiKey
        let media = store.media

        isStreaming = true
        streamText = ""
        defer { isStreaming = false }

        let throttle = StreamThrottle { chunk in streamText += chunk }

        do {
            let req = try await Task.detached(priority: .userInitiated, operation: { () throws -> URLRequest in
                var historyImages: [Data] = []
                for a in windowImages {
                    if let d = media.data(named: a.file) { historyImages.append(d) }
                }
                return try QwenAPI.makeRequest(baseURL: baseURL, key: key, model: model,
                                               messages: window, imageData: historyImages,
                                               stream: true)
            }).value
            let full = try await ChatRunner.shared.run(req) { chunk in throttle.receive(chunk) }
            throttle.cancel()
            streamText = ""
            if full.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(SearchMarker.token) {
                try await runWebSearch(question: history.last?.text ?? "", convID: convID, started: started)
                return
            }
            if !full.isEmpty {
                store.appendAssistant(full, model: model,
                                      elapsed: Date().timeIntervalSince(started), to: convID)
                maybeSpeak(full)
            }
        } catch let e as APIError {
            throttle.cancel()
            let fe = L.friendlyError(e.message, model: model, status: e.status)
            if let r = e.recoveredText, !r.isEmpty {
                store.appendAssistant(r + "\n\n\u{26a0}\u{fe0f} \(fe.message)", model: model,
                                      elapsed: Date().timeIntervalSince(started), to: convID)
            } else {
                alertError = fe
            }
            streamText = ""
        } catch {
            throttle.cancel()
            alertError = L.friendlyError(error.localizedDescription, model: model)
            streamText = ""
        }
    }

    @MainActor func runWebSearch(question: String, convID: UUID, started: Date) async throws {
        webStatus = L.t("web_searching")
        defer { webStatus = nil }
        let chatModel = settings.chatModel
        do {
            let urls = try await WebSearch.search(question)
            var hits: [WebHit] = []
            for (i, u) in urls.enumerated() {
                webStatus = "\(L.t("web_fetching")) (\(i + 1)/\(urls.count)) \(WebSearch.domain(of: u))"
                if let h = try? await WebSearch.fetchText(u) { hits.append(h) }
            }
            guard hits.count >= 2 else { throw APIError(message: L.t("web_no_results")) }
            let req = try WebSearch.makeAnswerRequest(baseURL: settings.baseURL, key: settings.apiKey,
                                                      model: chatModel, question: question, hits: hits)
            webStatus = L.t("web_searching")
            isStreaming = true
            streamText = ""
            let throttle = StreamThrottle { chunk in streamText += chunk }
            defer { isStreaming = false; streamText = ""; throttle.cancel() }
            let answer = try await ChatRunner.shared.run(req) { chunk in throttle.receive(chunk) }
            throttle.cancel()
            guard !answer.isEmpty else { throw APIError(message: L.t("web_no_answer")) }
            let sources = hits.map { WebSource(title: $0.title, url: $0.url, domain: $0.domain) }
            store.appendAssistant(answer, model: chatModel,
                                  elapsed: Date().timeIntervalSince(started), to: convID, sources: sources)
            maybeSpeak(answer)
        } catch {
            store.appendAssistant(AnswerError.other(error.localizedDescription, generic: L.t("err_web_generic")), model: chatModel,
                                  elapsed: Date().timeIntervalSince(started), to: convID)
        }
    }

    private func maybeSpeak(_ text: String) {
        guard settings.speakAnswers else { return }
        speech.speak(text: text, baseURL: settings.baseURL, key: settings.apiKey,
                     model: settings.audioModel, voice: settings.ttsVoice)
    }

    static func timeString(_ date: Date) -> String {
        let lang = L.lang
        if fmtCache[lang] == nil {
            let f = DateFormatter()
            f.locale = lang.locale
            f.dateFormat = L.timeFormat
            fmtCache[lang] = f
        }
        return fmtCache[lang]!.string(from: date)
    }

    @MainActor static func dayFormatter() -> DateFormatter {
        let lang = L.lang
        if dayFmtCache[lang] == nil {
            let f = DateFormatter()
            f.locale = lang.locale
            f.dateFormat = L.dayFormat
            dayFmtCache[lang] = f
        }
        return dayFmtCache[lang]!
    }

    @MainActor static var fmtCache: [AppLanguage: DateFormatter] = [:]
    @MainActor static var dayFmtCache: [AppLanguage: DateFormatter] = [:]
}
