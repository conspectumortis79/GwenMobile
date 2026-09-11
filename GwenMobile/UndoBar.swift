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
                .font(.system(size: 16))
                .foregroundStyle(Color.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(L.fmt("freed", StorageUsage.bytesText(receipt.freedBytes)))
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            Spacer(minLength: 8)
            Button(L.t("undo"), action: onUndo)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var detail: String {
        var parts: [String] = []
        if !receipt.conversations.isEmpty {
            parts.append("\(receipt.conversations.count) \(L.t("conversations_word"))")
        }
        if receipt.freedFiles > 0 {
            parts.append("\(receipt.freedFiles) \(L.t("images_word"))")
        }
        return parts.joined(separator: " · ")
    }
}
