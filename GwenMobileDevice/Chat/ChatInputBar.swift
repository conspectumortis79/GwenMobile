@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct ChatInputBar: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var voice: VoiceTranscriber
    @ObservedObject var busy: BusyOverlay
    @ObservedObject var speech: SpeechSynthesizer
    let isStreaming: Bool
    let isBusy: Bool
    let isRunning: Bool
    let chainIsRunning: Bool
    var conversationMode: Bool = false
    @Binding var input: String
    @Binding var attachMenu: Bool
    @Binding var pendingImages: [PendingPicture]
    @Binding var pendingFiles: [PendingFile]
    @FocusState.Binding var inputFocused: Bool
    let onStartSend: () -> Void
    let onStopRun: () -> Void
    let onToggleVoice: () -> Void
    var onRemovePendingFile: ((PendingFile) -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            inputStatusLines
            pendingAttachmentStrip
            inputControls
        }
        .background(Color(.secondarySystemBackground))
        .onChange(of: isStreaming) { _, value in if value { attachMenu = false } }
    }

    private var canSend: Bool {
        !isRunning && !isBusy && !isStreaming && !pendingFiles.contains(where: { $0.reading })
            && (!input.trimmed.isEmpty
            || !pendingImages.isEmpty || !pendingFiles.isEmpty)
    }

    var isStoppable: Bool {
        isStreaming || dictationBusy || chainIsRunning || isRunning
    }

    private var dictationBusy: Bool {
        !conversationMode && !voice.isCancelSession
            && (voice.state == .recording || voice.state == .processing)
    }

    private var voiceLine: String? {
        switch voice.state {
        case .waiting: return L.fmt("listen_waiting", settings.spokenWake)
        case .recording: return voice.liveText.isEmpty ? nil : voice.liveText
        case .idle, .processing: return nil
        }
    }

    private var micSymbol: String {
        switch voice.state {
        case .idle: return conversationMode ? "waveform" : "mic"
        case .processing: return "hourglass"
        case .waiting: return "ear"
        case .recording: return voice.isCancelSession ? "ear" : (conversationMode ? "waveform" : "mic.fill")
        }
    }

    private var micTint: Color {
        switch voice.state {
        case .recording: return voice.isCancelSession ? .blue : (conversationMode ? .blue : .red)
        case .waiting: return .blue
        case .idle, .processing: return conversationMode ? .blue : Color(.secondaryLabel)
        }
    }

    @ViewBuilder private var inputStatusLines: some View {
        if let line = voiceLine {
            Text(line)
                .scaledFont(13)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .transition(.opacity)
        }
        if voice.state == .recording, conversationMode, voice.liveText.isEmpty {
            Text(L.t("conversation_hint"))
                .scaledFont(11)
                .foregroundStyle(Color(.tertiaryLabel))
                .transition(.opacity)
        } else if voice.state == .recording, voice.isCancelSession {
            Text(L.fmt("listen_cancel_hint", settings.spokenCancel))
                .scaledFont(11)
                .foregroundStyle(Color(.tertiaryLabel))
                .transition(.opacity)
        } else if voice.state == .recording, !conversationMode {
            Text(L.fmt2("listen_hint", settings.spokenStop, settings.spokenCancel))
                .scaledFont(11)
                .foregroundStyle(Color(.tertiaryLabel))
                .transition(.opacity)
        }
        if voice.state == .recording, let left = voice.remaining, left <= 10 {
            Text(L.n("asr_countdown", left))
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(left <= 5 ? Color.red : Color(.secondaryLabel))
                .transition(.opacity)
        }
    }

    @ViewBuilder private var pendingAttachmentStrip: some View {
        if !pendingImages.isEmpty || !pendingFiles.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pendingImages) { item in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: item.image)
                                .resizable().scaledToFill()
                                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                            Button(action: TapProbe.action({ pendingImages.removeAll { $0.id == item.id } })) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .accessibilityLabel(L.t("attach_remove"))
                            .padding(3)
                        }
                    }
                    ForEach(pendingFiles) { file in
                        PendingFileCard(pending: file, onRemove: TapProbe.action({
                            if let onRemovePendingFile {
                                onRemovePendingFile(file)
                            } else {
                                pendingFiles.removeAll { $0.id == file.id }
                            }
                        }))
                    }
                }.padding(.horizontal)
            }
        }
    }

    private var inputControls: some View {
        HStack(alignment: .bottom, spacing: 8) {
            attachmentButton
            messageField
            voiceButton
            sendButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .animation(.easeInOut(duration: 0.15), value: speech.isSpeaking)
    }

    private var attachmentButton: some View {
        Button(action: TapProbe.action({
            if speech.isSpeaking {
                speech.stop()
            } else {
                withAnimation(.easeInOut(duration: 0.15)) { attachMenu.toggle() }
            }
        })) {
            Image(systemName: speech.isSpeaking ? "stop.fill" : "plus")
                .scaledFont(speech.isSpeaking ? 13 : 16, weight: .bold)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(speech.isSpeaking ? Color.red : Color(.systemGray3)))
                .accessibilityHidden(true)
        }
        .accessibilityLabel(speech.isSpeaking ? L.t("read_aloud_stop") : L.t("attach_photo"))
    }

    private var messageField: some View {
        TextField(L.t("message"), text: $input, axis: .vertical)
            .scaledFont(17)
            .lineLimit(1...6)
            .focused($inputFocused)
            .submitLabel(.send)
            .onChange(of: input) { _, typed in
                guard let message = ChatView.messageAfterReturn(typed) else { return }
                input = message
                onStartSend()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.systemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(.systemGray4), lineWidth: 0.7))
            )
    }

    private var voiceButton: some View {
        Button(action: TapProbe.action({ onToggleVoice() })) {
            Image(systemName: micSymbol)
                .scaledFont(19)
                .foregroundStyle(micTint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(voice.state == .recording
                                            ? (voice.isCancelSession ? Color.blue.opacity(0.12)
                                                                     : Color.red.opacity(0.12))
                                            : Color.clear))
        }
        .accessibilityLabel(L.t(voice.isCancelSession ? "cancel_word" : "dictate"))
        .accessibilityValue(voice.state == .recording ? L.t("state_on") : L.t("state_off"))
        .disabled(voice.state == .processing || isStreaming || busy.isBusy)
    }

    private var sendButton: some View {
        Button(action: TapProbe.action({
            if isStoppable {
                onStopRun()
            } else {
                onStartSend()
            }
        })) {
            Image(systemName: isStoppable ? "stop.fill" : "arrow.up")
                .scaledFont(16, weight: .bold)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(canSend || isStoppable ? Color.blue : Color(.systemGray3)))
        }
        .accessibilityLabel(isStoppable ? L.t("stop_running") : L.t("send"))
        .disabled(!canSend && !isStoppable)
    }
}

struct ChatAttachMenuCard: View {
    @ObservedObject var settings = AppSettings.shared
    @Binding var attachMenu: Bool
    @Binding var pendingItems: [PhotosPickerItem]
    let onMenuScan: () -> Void
    let onOpenFilePicker: () -> Void
    let onOpenVideoPicker: () -> Void
    let onPicked: ([PendingPicture]) -> Void
    var onOpenHelp: (() -> Void)? = nil
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        let photoLbl = L.t("attach_photo")
        let camLbl = L.t("camera")
        let readLbl = L.t("read_aloud")
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: TapProbe.action({ attachMenu = false; CameraPresenter.shared.present() })) {
                menuRow("camera", camLbl)
            }
            Button(action: TapProbe.action({ attachMenu = false; onMenuScan() })) {
                menuRow("doc.viewfinder", L.t("scan_menu"))
            }
            PhotosPicker(selection: $pendingItems, maxSelectionCount: ImagePolicy.maxAttachmentsPerMessage,
                         matching: .images) {
                menuRow("photo.on.rectangle.angled", photoLbl)
            }
            .onChange(of: pendingItems) { _, items in
                guard !items.isEmpty else { return }
                let batch = items
                pendingItems = []
                withAnimation(.easeInOut(duration: 0.15)) { attachMenu = false }
                let loaders = batch.map { PhotoPickerPort.makeItem?($0) ?? StubPickedItem() }
                let previous = importTask
                importTask = Task {
                    _ = await previous?.value
                    await PhotoPickerImporter(onPicked: onPicked).importPicked(loaders)
                }
            }
            Button(action: TapProbe.action({ attachMenu = false; onOpenFilePicker() })) {
                menuRow("doc.badge.plus", L.t("attach_file"))
            }
            Button(action: TapProbe.action({ attachMenu = false; onOpenVideoPicker() })) {
                menuRow("video.badge.plus", L.t("attach_video"))
            }
            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            Toggle(isOn: $settings.voice.speakAnswers) {
                menuLabel(settings.voice.speakAnswers ? "speaker.wave.2.fill" : "speaker.slash.fill",
                          readLbl)
            }
            .toggleStyle(.switch)
            .tint(.blue)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            if let onOpenHelp {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                Button(action: TapProbe.action({ attachMenu = false; onOpenHelp() })) {
                    menuRow("questionmark.circle", L.t("help_attach_row"))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
        .frame(width: 264, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.22), radius: 14, y: 6))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    nonisolated private func menuLabel(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .scaledFont(22)
                .foregroundStyle(Color(.secondaryLabel))
                .frame(width: 30)
                .accessibilityHidden(true)
            Text(label)
                .scaledFont(17)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    nonisolated private func menuRow(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 0) {
            menuLabel(symbol, label)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}
