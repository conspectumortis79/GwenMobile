@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import SwiftUI
import UIKit

@MainActor
struct UndoToast: View {
    let title: String
    let detail: String
    let onUndo: () -> Void
    let onExpire: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .scaledFont(16)
                .foregroundStyle(Color.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .scaledFont(13, weight: .semibold)
                    .lineLimit(1)
                Text(verbatim: detail)
                    .scaledFont(11)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(L.t("undo"), action: onUndo)
                .scaledFont(13, weight: .semibold)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
        .task {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            onExpire()
        }
    }
}
