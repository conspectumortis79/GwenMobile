import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentID: UUID?
    @Published private(set) var storageProblem: String?

    let media: MediaStore
    let images: ImageFeed
    lazy var cleaner = HistoryCleaner(store: self, media: media, feed: images)

    private let persistence: ConversationPersisting

    init(media: MediaStore = MediaStore(),
         paths: StoragePaths = StoragePaths(),
         persistence: ConversationPersisting? = nil) {
        self.media = media
        self.images = ImageFeed(reader: media)
        self.persistence = persistence ?? ConversationFilePersistence(url: paths.conversations)
        media.prepareDirectories()
        load()
        if conversations.isEmpty { newConversation() }
        currentID = conversations.first?.id
    }

    var current: Conversation? {
        conversations.first { $0.id == currentID }
    }

    func newConversation() {
        conversations.insert(Conversation(title: L.defaultTitle), at: 0)
        currentID = conversations.first?.id
        save()
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
        Set(conversations.flatMap { $0.messages.flatMap(\.imageFiles) })
    }

    func removeAllConversations() -> [(index: Int, conversation: Conversation)] {
        let removed = conversations.enumerated().map { (index: $0.offset, conversation: $0.element) }
        conversations = []
        newConversation()
        return removed
    }

    func appendMessage(_ msg: ChatMessage, to id: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        #if DEBUG
        RenderStats.appends.bump()
        #endif
        flowMark("APPEND role=\(msg.role.rawValue) chars=\(msg.text.count) imgs=\(msg.images.count) out=\(msg.outImages?.count ?? -1) msgs=\(conversations[idx].messages.count + 1)")
        conversations[idx].messages.append(msg)
        conversations[idx].updatedAt = Date()
        if L.defaultTitles.contains(conversations[idx].title), msg.role == .user, !msg.text.isEmpty {
            conversations[idx].title = String(msg.text.prefix(40))
        }
        save()
    }

    func appendAssistant(_ text: String, model: String?, elapsed: Double?, to id: UUID,
                         outImages: [Attachment]? = nil,
                         sources: [WebSource]? = nil,
                         thinking: ThinkingLevel? = nil) {
        appendMessage(ChatMessage(role: .assistant, text: text, model: model,
                                  elapsed: elapsed, outImages: outImages,
                                  sources: sources, thinking: thinking), to: id)
    }

    private func load() {
        guard let stored = persistence.load() else { return }
        conversations = stored.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var saveTask: Task<Void, Never>?
    private var writeGate: Task<Void, Never>?
    private var writeToken = 0
    private var writesInFlight = 0

    static let saveDebounce: Duration = .milliseconds(250)

    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        guard writesInFlight == 0 else {
            enqueueWrite(conversations, immediate: true)
            return
        }
        do {
            try persistence.persistNow(conversations)
            storageProblem = nil
        } catch {
            reportSaveFailure(error)
        }
    }

    private func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            self.enqueueWrite(self.conversations, immediate: false)
        }
    }

    private func enqueueWrite(_ snapshot: [Conversation], immediate: Bool) {
        let previous = writeGate
        let persistence = self.persistence
        writeToken += 1
        let token = writeToken
        writesInFlight += 1
        writeGate = Task { [weak self] in
            _ = await previous?.value
            do {
                if immediate { try persistence.persistNow(snapshot) }
                else { try await persistence.persist(snapshot) }
                self?.storageProblem = nil
            } catch {
                self?.reportSaveFailure(error)
            }
            self?.writesInFlight -= 1
            if self?.writeToken == token { self?.writeGate = nil }
        }
    }

    private func reportSaveFailure(_ error: Error) {
        storageProblem = L.t("storage_save_failed")
        flowLog.error("SAVE fehlgeschlagen \(error.localizedDescription, privacy: .public)")
    }

    func dismissStorageProblem() { storageProblem = nil }
}
