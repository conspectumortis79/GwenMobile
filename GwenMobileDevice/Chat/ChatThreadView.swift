@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct ChatThreadView: View {
    @EnvironmentObject private var store: ChatStore
    @ObservedObject var autoScroll: ChatAutoScroll
    @ObservedObject var busy: BusyOverlay
    @ObservedObject var voice: VoiceTranscriber
    @ObservedObject var routeDesk: RouteDesk
    @ObservedObject var gallerySelection: GallerySelection
    let sourceChecks: Set<UUID>
    let isStreaming: Bool
    let streamText: String
    let webStatus: String?
    @FocusState.Binding var inputFocused: Bool
    let actionsFor: (UUID) -> ChatThreadRowActions
    let onScrollProxy: (ScrollViewProxy) -> Void
    let onPlaceCall: (DialNumber) -> Void
    let onDropFiles: ([URL]) -> Void
    var onOpenHelp: (() -> Void)? = nil

    var body: some View {
        ScrollViewReader { proxy in
            let rows = statusRows
            let anchor = bottomAnchor(for: rows)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let conv = store.current {
                        if conv.messages.isEmpty && !isStreaming {
                            emptyHint
                        }
                        ChatThreadRowsView(messages: conv.messages, lastIsSettled: !isStreaming,
                                           reviewing: sourceChecks,
                                           media: store.media, documents: store.documents,
                                           photos: store.photos,
                                           actions: actionsFor(conv.id))
                            .equatable()
                        ForEach(rows) { row in
                            statusBubble(for: row).id(row.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .background(ChatThreadMetricsReader { metrics in
                    autoScroll.record(metrics, anchor: anchor, using: scrollAction(in: proxy))
                })
            }
            .scrollDismissesKeyboard(.immediately)
            .onAppear {
                onScrollProxy(proxy)
                autoScroll.reset(anchor, using: scrollAction(in: proxy))
            }
            .onChange(of: store.currentID) { _, _ in
                routeDesk.reset()
                gallerySelection.end()
                autoScroll.reset(anchor, using: scrollAction(in: proxy))
            }
            .simultaneousGesture(TapGesture().onEnded { inputFocused = false })
            .simultaneousGesture(
                DragGesture(minimumDistance: ChatAutoScroll.dragThreshold)
                    .onChanged { value in autoScroll.dragChanged(translation: value.translation.height) }
                    .onEnded { _ in autoScroll.dragEnded(anchor, using: scrollAction(in: proxy)) }
            )
            .onChange(of: streamText) { _, _ in followBottom(to: anchor, in: proxy) }
            .onChange(of: isStreaming) { _, _ in followBottom(to: anchor, in: proxy) }
            .onChange(of: voice.state) { _, state in
                if state == .processing { followBottom(to: anchor, in: proxy) }
            }
            .onChange(of: busy.isBusy) { _, _ in followBottom(to: anchor, in: proxy) }
            .onChange(of: busy.label) { _, _ in followBottom(to: anchor, in: proxy) }
            .onChange(of: webStatus) { _, _ in followBottom(to: anchor, in: proxy) }
            .onChange(of: store.current?.messages.count) { _, _ in followBottom(to: anchor, in: proxy) }
            .onChange(of: store.current?.messages.last?.pictures.count) { _, _ in
                followBottom(to: anchor, in: proxy)
            }
            .overlay(alignment: .bottomTrailing) {
                if autoScroll.showsReturnToBottom {
                    ReturnToBottomButton(action: TapProbe.action({
                        autoScroll.returnToBottom(anchor, using: scrollAction(in: proxy))
                    }))
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity)
                }
            }
        }
        .macFileDrop { onDropFiles($0) }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .scaledFont(40).foregroundStyle(.tertiary)
            Text(L.t("empty_hint"))
                .font(.subheadline).foregroundStyle(.secondary)
            if let onOpenHelp {
                Button(L.t("help_empty_action"), action: TapProbe.action({ onOpenHelp() }))
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func followBottom(to anchor: AnyHashable?, in proxy: ScrollViewProxy) {
        autoScroll.follow(anchor, using: scrollAction(in: proxy))
    }

    private func scrollAction(in proxy: ScrollViewProxy) -> ChatAutoScroll.ScrollAction {
        { anchor in proxy.scrollTo(anchor, anchor: .bottom) }
    }

    private var statusRows: [ChatThreadStatusRow] {
        ChatThreadStatusRow.present(
            streaming: isStreaming ? ChatMarkers.strip(streamText) : nil,
            transcribing: voice.state == .processing ? L.t("asr_preparing") : nil,
            processing: busy.isBusy ? busy.label : nil,
            researching: webStatus
        )
    }

    @ViewBuilder private func statusBubble(for row: ChatThreadStatusRow) -> some View {
        switch row {
        case .streaming(let text):
            streamingBubble(text)
        case .transcribing(let text), .processing(let text):
            StatusBubble(text: text)
        case .researching(let text):
            WebStatusBubble(text: text)
        }
    }

    private func streamingBubble(_ text: String) -> some View {
        var bubble = Bubble(text: text, isUser: false, question: liveQuestion, streaming: true)
        bubble.onCall = { number in onPlaceCall(number) }
        return bubble
    }

    private func bottomAnchor(for rows: [ChatThreadStatusRow]) -> AnyHashable? {
        ChatScrollAnchors.bottom(lastMessageID: store.current?.messages.last?.id, statusRows: rows)
    }

    private var liveQuestion: String? {
        store.current?.messages.last(where: { $0.role == .user })?.text
    }
}
