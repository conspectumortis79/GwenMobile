import SwiftUI

@MainActor
struct UndoBarHost: View {
    @ObservedObject var cleaner: HistoryCleaner

    var body: some View {
        if let receipt = cleaner.receipt {
            UndoBar(receipt: receipt) { cleaner.undoLast() }
        }
    }
}

@MainActor
struct UndoBar: View {
    let receipt: DeletionReceipt
    let onUndo: () -> Void

    var body: some View {
        UndoBanner(title: L.fmt("freed", StorageUsage.bytesText(receipt.freedBytes)),
                   detail: detailText, onUndo: onUndo)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
    }

    var detailText: String {
        let images = receipt.trashedFiles.count
        let files = receipt.trashedDocuments.count
        let exports = receipt.trashedExports.count
        return StorageUsage.joined([
            receipt.conversations.isEmpty ? nil : StorageUsage.counted(receipt.conversations.count,
                                                                      "conversations_word"),
            images == 0 ? nil : StorageUsage.counted(images, "images_word"),
            files == 0 ? nil : StorageUsage.counted(files, "files_word"),
            exports == 0 ? nil : StorageUsage.counted(exports, "exports_word"),
        ].compactMap { $0 })
    }
}
