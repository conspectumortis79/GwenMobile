import SwiftUI
import UIKit

@MainActor
struct UndoBanner: View {
    let title: String
    let detail: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .scaledFont(16)
                .foregroundStyle(Color.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .scaledFont(13, weight: .semibold)
                Text(verbatim: detail)
                    .scaledFont(11)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            Spacer(minLength: 8)
            Button(L.t("undo"), action: onUndo)
                .scaledFont(13, weight: .semibold)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
    }
}

@MainActor
struct UndoToastHost<Item: Identifiable>: ViewModifier where Item.ID: Hashable {
    let item: Item?
    let title: String
    let detail: (Item) -> String
    let onUndo: (Item) -> Void
    let onExpire: (Item) -> Void

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let item {
                    UndoBanner(title: title, detail: detail(item), onUndo: { onUndo(item) })
                        .lineLimit(1)
                        .overlay(RoundedRectangle(cornerRadius: 13)
                            .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
                        .task {
                            do {
                                try await Task.sleep(for: .seconds(5))
                            } catch {
                                return
                            }
                            onExpire(item)
                        }
                        .id(item.id)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: item?.id)
    }
}

extension View {
    func undoToastHost<Item: Identifiable>(item: Item?, title: String,
                                           detail: @escaping (Item) -> String,
                                           onUndo: @escaping (Item) -> Void,
                                           onExpire: @escaping (Item) -> Void) -> some View
        where Item.ID: Hashable {
        modifier(UndoToastHost(item: item, title: title, detail: detail, onUndo: onUndo, onExpire: onExpire))
    }
}
