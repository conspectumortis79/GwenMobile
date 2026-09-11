import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentID: UUID?

    let media: MediaStore
    let images: ImageFeed
    lazy var cleaner = HistoryCleaner(store: self, media: media, feed: images)

    private let paths: StoragePaths
    private let fileManager: FileManager

    init(media: MediaStore = MediaStore(),
         paths: StoragePaths = StoragePaths(),
         fileManager: FileManager = .default) {
        self.media = media
        self.images = ImageFeed(reader: media)
        self.paths = paths
        self.fileManager = fileManager
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
        Set(conversations.flatMap { c in
            c.messages.flatMap { m in m.images.map(\.file) + (m.outImages ?? []).map(\.file) }
        })
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
                         sources: [WebSource]? = nil) {
        appendMessage(ChatMessage(role: .assistant, text: text, model: model,
                                  elapsed: elapsed, outImages: outImages,
                                  sources: sources), to: id)
    }

    private func load() {
        guard let data = fileManager.contents(atPath: paths.conversations.path),
              let convs = try? JSONDecoder().decode([Conversation].self, from: data) else { return }
        conversations = convs.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var saveTask: Task<Void, Never>?

    private func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
    }

    private func saveNow() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: paths.conversations, options: .atomic)
    }
}
