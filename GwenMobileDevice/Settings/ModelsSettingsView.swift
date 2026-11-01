@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Binding var testResult: String?
    @State private var loadingModels = false

    var body: some View {
        Section {
            modelRow(.chat, title: L.t("chat_model"), selection: $settings.chatModel,
                     options: settings.profile.textCandidates)
            thinkingPicker
            modelRow(.vision, title: L.t("vision_model"), selection: $settings.visionModel,
                     options: settings.visionCandidates)
            modelRow(.image, title: L.t("image_model"), selection: $settings.imageModel,
                     options: settings.profile.imageCandidates)
            modelRow(.video, title: L.t("video_model"), selection: $settings.videoModel,
                     options: settings.videoCandidates)
            modelRow(.videoGeneration, title: L.t("video_generation_model"),
                     selection: $settings.videoGenerationModel,
                     options: settings.videoGenerationCandidates)
            SettingsBusyButton(title: L.t("load_models"),
                               busyTitle: L.t("loading_models"),
                               busy: loadingModels,
                               symbol: "arrow.clockwise",
                               enabled: settings.isConfigured, action: TapProbe.action({
                Task { await loadModels() }
            }))
        } header: {
            Text(L.t("models"))
        } footer: {
            Text(modelsFooter)
        }
        .task {
            if settings.profile.needsListing && settings.isConfigured {
                await loadModels()
            }
        }
        .onChange(of: settings.connectionIdentity) { old, new in
            guard settings.isConfigured, settings.descriptor.usesPresetURL(settings.connections) else {
                return
            }
            if old.provider != new.provider && !settings.profile.needsListing { return }
            Task { await loadModels() }
        }
    }

    private var modelsFooter: String {
        var lines = [settings.descriptor.modelsFooter]
        if !settings.availableModels.isEmpty {
            lines.append(L.counted(settings.availableModels.count, one: "models_footer_count_one",
                                   many: "models_footer_count"))
        }
        if settings.capabilities.image != .unavailable { lines.append(L.t("image_mode_hint")) }
        lines.append(thinkingFooterLine)
        lines.append(visionFooterLine)
        if settings.capabilities.video != .unavailable { lines.append(videoFooterLine) }
        if settings.capabilities.videoGeneration != .unavailable {
            lines.append(L.t("video_generation_footer"))
        }
        return lines.joined(separator: " ")
    }

    @ViewBuilder
    private func modelRow(_ feature: ProviderFeature, title: String, selection: Binding<String>,
                          options: [String]) -> some View {
        switch settings.capabilities[feature] {
        case .unavailable:
            LabeledContent(title) {
                Text(L.t("availability_unavailable"))
            }
            .foregroundStyle(.tertiary)
        case .available, .probed:
            if options.isEmpty && selection.wrappedValue.isEmpty {
                LabeledContent(title) {
                    Text(L.t("after_loading")).foregroundStyle(.secondary)
                }
            } else {
                modelPicker(title, selection: selection, options: options)
            }
        }
    }

    private func modelPicker(_ title: String, selection: Binding<String>,
                             options: [String]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.self) { Text(verbatim: $0).tag($0) }
            if !options.contains(selection.wrappedValue) {
                Text(verbatim: selection.wrappedValue).tag(selection.wrappedValue)
            }
        }
    }

    private var thinkingOptions: [ThinkingLevel] {
        let options = settings.capabilities(for: settings.chatModel).thinking.offeredLevels
        return options.contains(settings.chatThinkingLevel)
            ? options
            : options + [settings.chatThinkingLevel]
    }

    @ViewBuilder private var thinkingPicker: some View {
        Picker(L.t("thinking_depth"), selection: $settings.chatThinkingLevel) {
            ForEach(thinkingOptions, id: \.self) { level in
                Text(verbatim: level.label).tag(level)
            }
        }
    }

    private var thinkingFooterLine: String {
        let caps = settings.capabilities(for: settings.chatModel).thinking
        guard caps.isKnown else { return L.t("thinking_footer_unknown") }
        guard caps.offersControl else { return L.t("thinking_footer_none") }
        return L.counted(caps.offeredLevels.count - 1, one: "thinking_footer_probed_one",
                         many: "thinking_footer_probed")
    }

    private var visionFooterLine: String {
        guard settings.hasVisionCaps else { return L.t("vision_footer_unprobed") }
        let count = settings.visionCandidates.count
        return count == 0
            ? L.t("vision_footer_none")
            : L.counted(count, one: "vision_footer_count_one", many: "vision_footer_count")
    }

    private var videoFooterLine: String {
        guard settings.hasVideoCaps else { return L.t("video_footer_unprobed") }
        let count = settings.videoCandidates.count
        return count == 0
            ? L.t("video_footer_none")
            : L.counted(count, one: "video_footer_count_one", many: "video_footer_count")
    }

    @MainActor private func loadModels() async {
        AppSettings.flushKeySave()
        loadingModels = true
        testResult = nil
        defer { loadingModels = false }
        do {
            try await settings.reloadModels(of: settings.provider)
        } catch {
            testResult = L.t("models_error") + L.friendlyError(error.localizedDescription).message
        }
    }
}

struct SettingsBusyButton: View {
    let title: String
    let busyTitle: String
    let busy: Bool
    let symbol: String?
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if busy {
                HStack(spacing: 8) {
                    Text(busyTitle)
                    ProcessingDots(tint: Color.accentColor)
                }
            } else if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .disabled(busy || !enabled)
    }
}
