import GwenMobileKit
import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = [] {
        didSet { indexDirty = true }
    }
    @Published var currentID: UUID? {
        didSet {
            images.retain(only: Set(current?.messages.flatMap(\.storedImageFiles) ?? []))
        }
    }
    @Published private(set) var storageProblem: String?

    let media: MediaStore
    let documents: DocumentStore
    let exports: ExportStore
    let images: ImageFeed
    var photos: PhotoLibraryWriter
    let memory: MemoryStore
    private(set) var watches: PriceWatchStore
    #if DEBUG
    private var photosStandIn = DeskStandIn<PhotoLibraryWriter>()
    #endif
    lazy var cleaner = HistoryCleaner(store: self, media: media, documents: documents,
                                      exports: exports, feed: images)

    private let persistence: ConversationPersisting
    private var indexByID: [UUID: Int] = [:]
    private var indexDirty = false

    init(media: MediaStore = MediaStore(),
         documents: DocumentStore? = nil,
         exports: ExportStore? = nil,
         paths: StoragePaths = StoragePaths(),
         persistence: ConversationPersisting? = nil,
         photos: PhotoLibraryWriter? = nil,
         memory: MemoryStore? = nil,
         watches: PriceWatchStore? = nil) {
        self.memory = memory ?? MemoryStore(paths: paths)
        self.watches = watches ?? PriceWatchStore(paths: paths)
        self.media = media
        self.documents = documents ?? DocumentStore(paths: paths)
        self.exports = exports ?? ExportStore(paths: paths)
        self.images = ImageFeed(reader: media)
        self.photos = photos ?? PhotoLibraryWriter()
        self.persistence = persistence
            ?? ConversationFolderPersistence(
                folder: paths.conversationsFolder,
                legacy: ConversationFilePersistence(url: paths.conversations,
                                                     legacyURL: paths.storedConversationsBeforeMove))
        media.prepareDirectories()
        self.documents.prepareDirectories()
        self.exports.prepareDirectories()
        media.emptyTrash()
        OcrTextStore.removeStoredText(from: [paths.ocr, paths.storedOCRBeforeMove,
                                            OcrTextStore.temporaryRoot])
        load()
        if conversations.isEmpty { newConversation() }
        currentID = conversations.first?.id
        indexDirty = true
        wireStoreFailures()
    }

    private func wireStoreFailures() {
        let memory = self.memory
        let watches = self.watches
        Task { [weak self] in
            await memory.reportFailures { [weak self] _ in
                Task { @MainActor in self?.noteStoreFailure() }
            }
            await watches.reportFailures { [weak self] _ in
                Task { @MainActor in self?.noteStoreFailure() }
            }
        }
    }

    private func noteStoreFailure() {
        storeFailure = true
        storageProblem = L.t("storage_save_failed")
    }

    #if DEBUG
    func stand(in photos: PhotoLibraryWriter) {
        photosStandIn.stand(photos, over: &self.photos)
    }

    func restorePhotos() {
        photosStandIn.restore(&photos)
    }
    #endif

    var current: Conversation? {
        guard let index = currentIndex else { return nil }
        return conversations.indices.contains(index) ? conversations[index] : nil
    }

    private var currentIndex: Int? {
        guard let currentID else { return nil }
        if indexDirty { rebuildIndex() }
        return indexByID[currentID]
    }

    private func rebuildIndex() {
        var map: [UUID: Int] = [:]
        map.reserveCapacity(conversations.count)
        for (index, conversation) in conversations.enumerated() { map[conversation.id] = index }
        indexByID = map
        indexDirty = false
    }

    func newConversation() {
        conversations.insert(Conversation(title: L.defaultTitle), at: 0)
        currentID = conversations.first?.id
        save()
    }

    func startFreshConversation() {
        guard current?.messages.isEmpty != true else { return }
        newConversation()
    }

    func removeConversation(_ id: UUID) -> (index: Int, conversation: Conversation)? {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return nil }
        let conversation = conversations.remove(at: idx)
        if currentID == id { currentID = conversations.first?.id }
        if conversations.isEmpty { newConversation() }
        save()
        return (idx, conversation)
    }

    func restoreConversation(at index: Int, _ conversation: Conversation) {
        let at = min(max(index, 0), conversations.count)
        conversations.insert(conversation, at: at)
        if currentID == nil { currentID = conversation.id }
        save()
    }

    func removeMessage(_ id: UUID, from conversation: UUID) -> (index: Int, message: ChatMessage)? {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversation }),
              let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == id }) else { return nil }
        let message = conversations[cIdx].messages.remove(at: mIdx)
        conversations[cIdx].updatedAt = Date()
        save()
        return (mIdx, message)
    }

    func restoreMessage(_ message: ChatMessage, to conversation: UUID, at index: Int) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversation }) else { return }
        let at = min(max(index, 0), conversations[cIdx].messages.count)
        conversations[cIdx].messages.insert(message, at: at)
        save()
    }

    var referencedFiles: Set<String> {
        Set(conversations.flatMap { $0.messages.flatMap(\.storedImageFiles) })
    }

    var referencedDocuments: Set<String> {
        Set(conversations.flatMap { $0.messages.flatMap(\.documentFiles) })
    }

    func removeAllConversations() -> [(index: Int, conversation: Conversation)] {
        let removed = conversations.enumerated().map { (index: $0.offset, conversation: $0.element) }
        conversations = []
        newConversation()
        return removed
    }

    @discardableResult
    func appendMessage(_ msg: ChatMessage, to id: UUID) -> Bool {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return false }
        #if DEBUG
        RenderStats.appends.bump()
        #endif
        flowMark("APPEND role=\(msg.role.rawValue) chars=\(msg.text.count) imgs=\(msg.images.count) out=\(msg.outImages?.count ?? -1) msgs=\(conversations[idx].messages.count + 1) bildergal=\(msg.gallery?.pictures.count ?? -1)")
        conversations[idx].messages.append(msg)
        conversations[idx].updatedAt = Date()
        if L.defaultTitles.contains(conversations[idx].title), msg.role == .user, !msg.text.isEmpty {
            conversations[idx].title = Self.title(of: msg.text)
        }
        save()
        return true
    }

    @discardableResult
    func appendAssistant(_ text: String, model: String?, elapsed: Double?, to id: UUID,
                         outImages: [Attachment]? = nil,
                         files: [AttachedFile]? = nil,
                         sources: [WebSource]? = nil,
                         sourcesHeadingKey: String? = nil,
                         sourceReview: SourceReview? = nil,
                         thinking: ThinkingLevel? = nil,
                         placeGroups: [PlaceGroup]? = nil,
                         fileRefs: [FileRef]? = nil,
                         fileRefsHeadingKey: String? = nil,
                         gallery: PictureGallery? = nil,
                         calendar: CalendarRef? = nil,
                         reminder: ReminderRef? = nil,
                         memoryRefs: [MemoryRef]? = nil,
                         weather: WeatherRef? = nil,
                         priceWatch: PriceWatchRef? = nil,
                         briefing: DayBriefingRef? = nil) -> UUID? {
        let message = ChatMessage(role: .assistant, text: text, model: model,
                                  elapsed: elapsed, outImages: outImages,
                                  sources: sources, sourcesHeadingKey: sourcesHeadingKey,
                                  sourceReview: sourceReview,
                                  thinking: thinking, placeGroups: placeGroups,
                                  files: files ?? [],
                                  fileRefs: fileRefs, fileRefsHeadingKey: fileRefsHeadingKey,
                                  gallery: gallery, calendarRef: calendar, reminderRef: reminder,
                                  memoryRefs: memoryRefs, weatherRef: weather,
                                  priceWatchRef: priceWatch, dayBriefingRef: briefing)
        guard appendMessage(message, to: id) else { return nil }
        return message.id
    }

    func replaceAssistant(_ id: UUID, in conversation: UUID, with fresh: ChatMessage) {
        guard updateMessage(id, in: conversation, { $0.applyAnswer(from: fresh) }) else { return }
        flowMark("ERWEITERT nachricht=\(id.uuidString.prefix(8)) chars=\(fresh.text.count) "
                 + "out=\(fresh.outImages?.count ?? -1) bildergal=\(fresh.gallery?.pictures.count ?? -1)")
    }

    @discardableResult
    func updateAssistantMessage(_ id: UUID, in conversation: UUID,
                                _ change: (inout ChatMessage) -> Void) -> Bool {
        updateMessage(id, in: conversation, change)
    }

    func attachScan(_ file: AttachedFile, to message: UUID, in conversation: UUID) {
        guard updateMessage(message, in: conversation, { $0.files.append(file) }) else { return }
        flowMark("SCAN angehaengt name=\(file.name) seiten=\(file.pages ?? -1) zeichen=\(file.chars)")
    }

    func attachScanRef(_ file: AttachedFile, to message: UUID, in conversation: UUID) {
        guard updateMessage(message, in: conversation, { $0.scanRef = file }) else { return }
        flowMark("SCAN pdf geteilt name=\(file.name)")
    }

    func attachReminderOffer(_ offer: ScanReminderOffer, to message: UUID, in conversation: UUID) {
        guard updateMessage(message, in: conversation, { $0.reminderOffer = offer }) else { return }
        flowMark("SCAN erinnerung angeboten titel=\(offer.title) faellig=\(offer.chipStamp ?? "-")")
    }

    func settleReminderOffer(_ ref: ReminderRef?, to message: UUID, in conversation: UUID) {
        guard updateMessage(message, in: conversation, { existing in
            existing.reminderOffer = nil
            if let ref { existing.reminderRef = ref }
        }) else { return }
        flowMark("SCAN erinnerung erledigt angelegt=\(ref != nil)")
    }

    @discardableResult
    private func updateMessage(_ message: UUID, in conversation: UUID,
                               _ change: (inout ChatMessage) -> Void) -> Bool {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversation }),
              let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == message })
        else { return false }
        change(&conversations[cIdx].messages[mIdx])
        conversations[cIdx].updatedAt = Date()
        save()
        return true
    }

    static func title(of text: String) -> String {
        let oneLine = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return String(oneLine.prefix(40))
    }

    private func load() {
        switch persistence.load() {
        case .nothing:
            return
        case .loaded(let stored):
            conversations = stored.sorted { $0.updatedAt > $1.updatedAt }
        case .recovered(let stored, let whereAbout):
            conversations = stored.sorted { $0.updatedAt > $1.updatedAt }
            flowLog.error("HISTORIE gerettet datei=\(whereAbout.lastPathComponent, privacy: .public)")
            loadProblem = L.fmt("storage_recovered", whereAbout.lastPathComponent)
            storageProblem = loadProblem
        case .quarantined(let whereAbout):
            flowLog.error("HISTORIE unlesbar datei=\(whereAbout.lastPathComponent, privacy: .public)")
            loadProblem = L.t("storage_load_failed")
            storageProblem = loadProblem
        }
    }

    private var saveTask: Task<Void, Never>?
    private var writeGate: Task<Void, Never>?
    private var loadProblem: String?
    private var storeFailure = false

    static let saveDebounce: Duration = .milliseconds(250)

    func flushPendingSave() async {
        saveTask?.cancel()
        saveTask = nil
        await enqueueWrite(conversations).value
    }

    private func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            self.enqueueWrite(self.conversations)
        }
    }

    @discardableResult
    private func enqueueWrite(_ snapshot: [Conversation]) -> Task<Void, Never> {
        let previous = writeGate
        let persistence = self.persistence
        let gate = Task { [weak self] in
            _ = await previous?.value
            do {
                try await persistence.persist(snapshot)
                self?.clearSaveFailure()
            } catch {
                self?.reportSaveFailure(error)
            }
        }
        writeGate = gate
        return gate
    }

    private func clearSaveFailure() {
        if loadProblem == nil, !storeFailure { storageProblem = nil }
    }

    private func reportSaveFailure(_ error: Error) {
        storageProblem = L.t("storage_save_failed")
        flowLog.error("SAVE fehlgeschlagen \(error.localizedDescription, privacy: .public)")
    }

    func dismissStorageProblem() { storageProblem = nil; loadProblem = nil; storeFailure = false }

    func updateGallery(_ messageID: UUID, in conversation: UUID, _ gallery: PictureGallery) {
        _ = updateMessage(messageID, in: conversation) { $0.gallery = gallery }
    }

    @discardableResult
    func updateSourceReview(_ review: SourceReview, messageID: UUID, in conversation: UUID) -> Bool {
        let applied = updateMessage(messageID, in: conversation) { $0.sourceReview = review }
        if applied {
            flowMark("PRUEFUNG eingetragen nachricht=\(messageID.uuidString.prefix(8)) "
                     + "verifiziert=\(review.verified) geprueft=\(review.checkedClaims) "
                     + "unbelegt=\(review.unsupported.count) widersprochen=\(review.contradicted.count)")
        }
        return applied
    }

    #if DEBUG
    private var watchesStandIn = DeskStandIn<PriceWatchStore>()

    func stand(in watches: PriceWatchStore) {
        watchesStandIn.stand(watches, over: &self.watches)
    }

    func restoreWatches() {
        watchesStandIn.restore(&watches)
    }
    #endif
}
