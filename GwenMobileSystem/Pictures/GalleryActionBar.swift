@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI

struct GalleryActionBar: View {
    let plan: GalleryBarPlan
    let onSave: () -> Void
    let onShare: () -> Void
    let onSaveAll: () -> Void
    let onCancel: () -> Void

    var body: some View {
        #if targetEnvironment(macCatalyst)
        macBody
        #else
        phoneBody
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private var macBody: some View {
        HStack(spacing: 8) {
            if plan.isConfirmation {
                Image(systemName: plan.resultSymbol)
                    .scaledFont(13)
                    .foregroundStyle(.white)
                Text(verbatim: plan.statusLine)
                    .scaledFont(12.5, weight: .semibold)
                    .foregroundStyle(.white)
            } else {
                dockButton(plan.saveTitle, symbol: "square.and.arrow.down", filled: true,
                           enabled: plan.canAct, action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
                dockButton(plan.shareTitle, symbol: "square.and.arrow.up",
                           enabled: plan.canAct, action: onShare)
                if plan.showsSaveAll {
                    dockButton(plan.saveAllTitle, symbol: "tray.and.arrow.down",
                               enabled: plan.canAct, action: onSaveAll)
                }
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: plan.statusLine)
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(.white)
                    Text(verbatim: plan.shortcutLine)
                        .scaledFont(10.5)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .scaledFont(11, weight: .bold)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("cancel"))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(red: 0.15, green: 0.15, blue: 0.16).opacity(0.96)))
        .shadow(color: Color.black.opacity(0.3), radius: 16, y: 8)
        .overlay(alignment: .bottom) {
            if let progress = plan.progress {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .padding(.horizontal, 8)
            }
        }
    }

    private func dockButton(_ title: String, symbol: String, filled: Bool = false,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).scaledFont(11)
                Text(verbatim: title).scaledFont(12, weight: .semibold)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(filled ? Color(red: 0.04, green: 0.52, blue: 1) : Color.white.opacity(0.12)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
    #else
    private var phoneBody: some View {
        VStack(spacing: 8) {
            if plan.isConfirmation {
                HStack(spacing: 7) {
                    Image(systemName: plan.resultSymbol)
                        .scaledFont(13)
                        .foregroundStyle(plan.resultTint)
                    Text(verbatim: plan.statusLine)
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(Color(.label))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            } else {
                statusRow
                actionRow
                if let progress = plan.progress {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color(.separator), lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Text(verbatim: plan.statusLine)
                .scaledFont(12.5, weight: .semibold)
                .foregroundStyle(Color(.label))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            Button(action: onCancel) {
                Text(verbatim: plan.cancelTitle)
                    .scaledFont(12.5, weight: .semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(.secondaryLabel))
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 3)
    }

    private var actionRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                actionButton(plan.saveTitle, symbol: "square.and.arrow.down",
                             background: Color.blue, tint: .white, action: onSave)
                actionButton(plan.shareTitle, symbol: "square.and.arrow.up",
                             background: Color(.secondarySystemBackground), tint: Color(.label), action: onShare)
            }
            if plan.showsSaveAll {
                actionButton(plan.saveAllTitle, symbol: "tray.and.arrow.down",
                             background: Color(.secondarySystemBackground), tint: Color(.label), action: onSaveAll)
            }
        }
    }

    private func actionButton(_ title: String, symbol: String, background: Color, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title, symbol: symbol, background: background, tint: tint)
        }
        .buttonStyle(.plain)
        .disabled(!plan.canAct)
        .opacity(plan.canAct ? 1 : 0.5)
    }

    private func actionLabel(_ title: String, symbol: String, background: Color,
                             tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).scaledFont(13)
            Text(verbatim: title).scaledFont(13, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(background))
        .foregroundStyle(tint)
    }
    #endif
}
