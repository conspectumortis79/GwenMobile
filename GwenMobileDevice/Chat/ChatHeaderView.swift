@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct ChatHeaderView: View {
    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var gallerySelection: GallerySelection
    @ObservedObject private var settings = AppSettings.shared
    @Binding var showHistory: Bool
    @Binding var showSettings: Bool
    let onNewChat: () -> Void
    let onToggleListen: () -> Void
    var onToggleConversation: () -> Void = {}
    let onCancelGallery: () -> Void

    var body: some View {
        #if targetEnvironment(macCatalyst)
        chrome(row {
            Text(store.current?.title ?? L.t("new_chat"))
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
        })
        #else
        chrome(VStack(spacing: 2) {
            row {}
            Text(store.current?.title ?? L.t("new_chat"))
                .scaledFont(13)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
                .padding(.top, 2)
        })
        #endif
    }

    private func row<Content: View>(@ViewBuilder _ leading: () -> Content) -> some View {
        HStack(spacing: 7) {
            leading()
            Spacer(minLength: 8)
            if gallerySelection.isPicking {
                cancelButton
            } else {
                button("square.and.pencil", label: L.t("new_chat")) { onNewChat() }
                button("list.bullet", label: L.t("history")) { showHistory = true }
                button("ear", label: L.t("listen_mode"), active: settings.voice.listenMode) { onToggleListen() }
                    .accessibilityValue(settings.voice.listenMode ? L.t("state_on") : L.t("state_off"))
                button("waveform", label: L.t("conversation_mode"), active: settings.voice.conversationMode) {
                    onToggleConversation()
                }
                .accessibilityValue(settings.voice.conversationMode ? L.t("state_on") : L.t("state_off"))
                button("gearshape", label: L.t("settings")) { showSettings = true }
            }
        }
        .frame(height: 36)
        .foregroundStyle(Color.primary)
    }

    private var cancelButton: some View {
        Button(action: onCancelGallery) {
            Text(verbatim: L.t("cancel"))
                .scaledFont(13, weight: .semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color(.systemGray5)))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
    }

    private func chrome<Content: View>(_ content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(Color(.secondarySystemBackground))
            .overlay(Divider(), alignment: .bottom)
    }

    private func button(_ symbol: String, label: String, active: Bool = false,
                        _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(20)
                .foregroundStyle(active ? Color.white : Color.primary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(active ? Color.blue : Color(.systemGray5)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .padding(.leading, 8)
        .animation(.easeInOut(duration: 0.15), value: active)
    }
}

struct ChatNoticeOverlay: View {
    @ObservedObject var notice: NoticeLine

    var body: some View {
        if let note = notice.text {
            Text(verbatim: note)
                .scaledFont(13, weight: .medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.72)))
                .padding(.bottom, 10)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}
