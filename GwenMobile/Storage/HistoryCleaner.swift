import GwenMobileKit
import Foundation

struct SweepRollback {
    let placeholder: UUID
    let previousCurrentID: UUID?
}

struct DeletionReceipt {
    var conversations: [(index: Int, conversation: Conversation)] = []
    var messages: [(conversation: UUID, index: Int, message: ChatMessage)] = []
    var trashedFiles: [TrashedFile] = []
    var trashedDocuments: [TrashedFile] = []
    var trashedExports: [TrashedExport] = []
    var sweep: SweepRollback?
    var freedBytes = 0
    var freedFiles = 0
}

@MainActor
final class HistoryCleaner: ObservableObject {
    static let defaultUndoWindow = Duration.seconds(5)

    @Published private(set) var usage = StorageUsage()
    @Published private(set) var receipt: DeletionReceipt?

    private struct PendingDeletion {
        let id: UUID
        let receipt: DeletionReceipt
        var expiry: Task<Void, Never>?

        init(receipt: DeletionReceipt) {
            id = UUID()
            self.receipt = receipt
        }
    }

    private let store: ChatStore
    private let media: MediaStore
    private let documents: DocumentStore
    private let exports: ExportStore
    private let feed: ImageFeed
    private let undoWindow: Duration
    private var pending: [PendingDeletion] = []

    init(store: ChatStore, media: MediaStore, documents: DocumentStore, exports: ExportStore,
         feed: ImageFeed, undoWindow: Duration = HistoryCleaner.defaultUndoWindow) {
        self.store = store
        self.media = media
        self.documents = documents
        self.exports = exports
        self.feed = feed
        self.undoWindow = undoWindow
    }

    func refreshUsage() async {
        let conversations = store.conversations
        let media = self.media
        let documents = self.documents
        let exports = self.exports
        let measured = await Offload.value(priority: .utility) {
            StorageMeasurement.usage(conversations: conversations, images: media,
                                     documents: documents, exports: exports)
        }
        usage = measured
    }

    func deleteMessage(_ id: UUID, in conversation: UUID) {
        guard let removed = store.removeMessage(id, from: conversation) else { return }
        var receipt = DeletionReceipt()
        receipt.messages = [(conversation, removed.index, removed.message)]
        finish(&receipt, with: [removed.message])
    }

    func deleteConversation(_ id: UUID) {
        let previousCurrentID = store.currentID
        let removesTheLastOne = store.conversations.count == 1
        guard let removed = store.removeConversation(id) else { return }
        var receipt = DeletionReceipt()
        receipt.conversations = [(removed.index, removed.conversation)]
        if removesTheLastOne, let placeholder = store.currentID {
            receipt.sweep = SweepRollback(placeholder: placeholder, previousCurrentID: previousCurrentID)
        }
        finish(&receipt, with: removed.conversation.messages)
    }

    func deleteAllConversations() {
        var receipt = DeletionReceipt()
        let previousCurrentID = store.currentID
        let removed = store.removeAllConversations()
        receipt.conversations = removed
        if let placeholder = store.currentID, !removed.isEmpty {
            receipt.sweep = SweepRollback(placeholder: placeholder, previousCurrentID: previousCurrentID)
        }
        let sweptExports = exports.moveAllToTrash()
        finish(&receipt, with: removed.flatMap { $0.conversation.messages }, exports: sweptExports)
    }

    func undoLast() {
        guard let last = pending.popLast() else { return }
        last.expiry?.cancel()
        let restored = last.receipt
        for entry in restored.conversations.reversed() {
            store.restoreConversation(at: entry.index, entry.conversation)
        }
        for entry in restored.messages {
            store.restoreMessage(entry.message, to: entry.conversation, at: entry.index)
        }
        media.restoreFromTrash(restored.trashedFiles)
        documents.restoreFromTrash(restored.trashedDocuments)
        exports.restoreFromTrash(restored.trashedExports)
        dropFreshPlaceholder(restored)
        showNewestPending()
        Task { await refreshUsage() }
    }

    private static let deletionNoticeTexts: Set<String> = {
        guard let texts = L.strings["history_deleted"] else { return [] }
        return Set(texts.values)
    }()

    private func dropFreshPlaceholder(_ receipt: DeletionReceipt) {
        guard let sweep = receipt.sweep else { return }
        if let fresh = store.conversations.first(where: { $0.id == sweep.placeholder }) {
            guard fresh.messages.isEmpty || onlyDeletionNotice(fresh) else { return }
            _ = store.removeConversation(sweep.placeholder)
        }
        guard store.conversations.contains(where: { $0.id == sweep.previousCurrentID }) else { return }
        store.currentID = sweep.previousCurrentID
    }

    private func onlyDeletionNotice(_ conversation: Conversation) -> Bool {
        guard conversation.messages.count == 1, let message = conversation.messages.first,
              message.role == .assistant else { return false }
        return Self.deletionNoticeTexts.contains(message.text)
    }

    #if DEBUG
    func discardPendingDeletion() {
        for entry in pending { entry.expiry?.cancel() }
        let sweeping = pending
        pending = []
        for entry in sweeping { discard(entry.receipt) }
        showNewestPending()
        guard !sweeping.isEmpty else { return }
        Task { await refreshUsage() }
    }
    #endif

    private func discard(_ swept: DeletionReceipt) {
        media.discardTrashed(swept.trashedFiles)
        documents.discardTrashed(swept.trashedDocuments)
        exports.discardTrashed(swept.trashedExports)
    }

    private func showNewestPending() {
        receipt = pending.last?.receipt
    }

    private func finish(_ receipt: inout DeletionReceipt, with messages: [ChatMessage],
                        exports swept: [TrashedExport] = []) {
        let doomed = unreferencedVictims(of: messages)
        receipt.trashedFiles = media.moveImagesToTrash(doomed.filter(media.hasImage))
        receipt.trashedDocuments = documents.moveFilesToTrash(doomed.filter { !media.hasImage($0) })
        receipt.trashedExports = swept
        let trashed = receipt.trashedFiles + receipt.trashedDocuments
        receipt.freedBytes = trashed.reduce(0) { $0 + $1.bytes } + swept.reduce(0) { $0 + $1.bytes }
        receipt.freedFiles = trashed.count + swept.count
        for entry in receipt.trashedFiles { feed.forget(entry.file) }
        self.receipt = receipt
        let window = undoWindow
        pending.append(PendingDeletion(receipt: receipt))
        let slot = pending.index(before: pending.endIndex)
        let token = pending[slot].id
        pending[slot].expiry = Task { [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            self?.expire(token)
        }
        Task { await refreshUsage() }
    }

    private func expire(_ id: UUID) {
        guard let position = pending.firstIndex(where: { $0.id == id }) else { return }
        let entry = pending.remove(at: position)
        discard(entry.receipt)
        showNewestPending()
        Task { await refreshUsage() }
    }

    private func unreferencedVictims(of messages: [ChatMessage]) -> [String] {
        let removed = Set(messages.flatMap { $0.storedImageFiles + $0.documentFiles })
        return Array(removed.subtracting(store.referencedFiles).subtracting(store.referencedDocuments))
    }
}
