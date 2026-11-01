@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
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
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .scaledFont(16)
                .foregroundStyle(Color.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(L.fmt("freed", StorageUsage.bytesText(receipt.freedBytes)))
                    .scaledFont(13, weight: .semibold)
                Text(detailText)
                    .scaledFont(11)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            Spacer(minLength: 8)
            Button(L.t("undo"), action: onUndo)
                .scaledFont(13, weight: .semibold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
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
