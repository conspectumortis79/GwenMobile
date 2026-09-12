import Foundation

struct SweepRollback {
    let placeholder: UUID
    let previousCurrentID: UUID?
}

struct DeletionReceipt {
    var conversations: [(index: Int, conversation: Conversation)] = []
    var messages: [(conversation: UUID, index: Int, message: ChatMessage)] = []
    var trashedFiles: [String] = []
    var sweep: SweepRollback?
    var freedBytes = 0
    var freedFiles = 0
}

@MainActor
final class HistoryCleaner: ObservableObject {
    static let defaultUndoWindow = Duration.seconds(5)

    @Published private(set) var usage = StorageUsage()
    @Published private(set) var receipt: DeletionReceipt?

    private let store: ChatStore
    private let media: MediaStore
    private let feed: ImageFeed
    private let undoWindow: Duration
    private var undoTask: Task<Void, Never>?

    init(store: ChatStore, media: MediaStore, feed: ImageFeed,
         undoWindow: Duration = HistoryCleaner.defaultUndoWindow) {
        self.store = store
        self.media = media
        self.feed = feed
        self.undoWindow = undoWindow
    }

    func refreshUsage() async {
        let conversations = store.conversations
        let media = self.media
        let measured = await Task.detached(priority: .utility) {
            StorageMeasurement.usage(conversations: conversations, inventory: media)
        }.value
        usage = measured
    }

    func deleteMessage(_ id: UUID, in conversation: UUID) {
        guard let removed = store.removeMessage(id, from: conversation) else { return }
        var receipt = newReceipt()
        receipt.messages = [(conversation, removed.index, removed.message)]
        finish(&receipt, with: [removed.message])
    }

    func deleteConversation(_ id: UUID) {
        guard let removed = store.removeConversation(id) else { return }
        var receipt = newReceipt()
        receipt.conversations = [(removed.index, removed.conversation)]
        finish(&receipt, with: removed.conversation.messages)
    }

    func deleteAllConversations() {
        var receipt = newReceipt()
        let previousCurrentID = store.currentID
        let removed = store.removeAllConversations()
        receipt.conversations = removed
        if let placeholder = store.currentID, !removed.isEmpty {
            receipt.sweep = SweepRollback(placeholder: placeholder, previousCurrentID: previousCurrentID)
        }
        finish(&receipt, with: removed.flatMap { $0.conversation.messages })
    }

    func undoLast() {
        undoTask?.cancel()
        undoTask = nil
        guard let receipt else { return }
        for entry in receipt.conversations.reversed() {
            store.restoreConversation(at: entry.index, entry.conversation)
        }
        for entry in receipt.messages {
            store.restoreMessage(entry.message, to: entry.conversation, at: entry.index)
        }
        media.restoreFromTrash(receipt.trashedFiles)
        dropFreshPlaceholder(receipt)
        self.receipt = nil
        Task { await refreshUsage() }
    }

    private func dropFreshPlaceholder(_ receipt: DeletionReceipt) {
        guard let sweep = receipt.sweep else { return }
        _ = store.removeConversation(sweep.placeholder)
        guard store.conversations.contains(where: { $0.id == sweep.previousCurrentID }) else { return }
        store.currentID = sweep.previousCurrentID
    }

    func discardPendingDeletion() {
        undoTask?.cancel()
        undoTask = nil
        guard receipt != nil else { return }
        media.emptyTrash()
        receipt = nil
    }

    private func newReceipt() -> DeletionReceipt {
        discardPendingDeletion()
        return DeletionReceipt()
    }

    private func finish(_ receipt: inout DeletionReceipt, with messages: [ChatMessage]) {
        let doomed = unreferencedVictims(of: messages)
        receipt.freedBytes = doomed.reduce(0) { $0 + media.byteSize(of: $1) }
        receipt.freedFiles = doomed.count
        receipt.trashedFiles = media.moveImagesToTrash(doomed)
        for file in doomed { feed.forget(file) }
        self.receipt = receipt
        Task { await refreshUsage() }
        let window = undoWindow
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            self?.discardPendingDeletion()
        }
    }

    private func unreferencedVictims(of messages: [ChatMessage]) -> [String] {
        Array(Set(messages.flatMap(\.imageFiles)).subtracting(store.referencedFiles))
    }
}
