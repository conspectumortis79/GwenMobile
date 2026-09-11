import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @EnvironmentObject private var cleaner: HistoryCleaner
    @Environment(\.dismiss) private var dismiss
    @State private var testResult: String?
    @State private var confirmDeleteAll = false
    @State private var testing = false
    @State private var loadingModels = false

    private var textModels: [String] { ModelFilter.textCandidates(settings.availableModels) }
    private var imageModels: [String] { ModelFilter.imageCandidates(settings.availableModels) }
    private var audioModels: [String] { ModelFilter.audioCandidates(settings.availableModels) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(verbatim: "\(lang.flag)  \(lang.label)").tag(lang)
                        }
                    } label: {
                        Label(L.t("language"), systemImage: "globe")
                    }
                } header: {
                    Text(L.t("language"))
                } footer: {
                    Text(L.t("language_footer"))
                }

                Section {
                    SecureField("sk-…", text: $settings.apiKey)
                } header: {
                    Text(L.t("api_key"))
                } footer: {
                    Link(L.t("create_key"),
                         destination: URL(string: "https://home.qwencloud.com/api-keys")!)
                }

                Section {
                    Picker(L.t("endpoint"), selection: $settings.baseURL) {
                        ForEach(AppSettings.knownEndpoints) { ep in
                            Text(verbatim: ep.label).tag(ep.url)
                        }
                        if !AppSettings.knownEndpoints.contains(where: { $0.url == settings.baseURL }) {
                            Text(verbatim: settings.baseURL).tag(settings.baseURL)
                        }
                    }
                    TextField(L.t("base_url"), text: $settings.baseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.footnote.monospaced())
                } header: {
                    Text(L.t("endpoint"))
                } footer: {
                    Text(L.t("endpoint_footer"))
                }

                Section {
                    modelPicker(L.t("chat_model"), selection: $settings.chatModel, options: textModels)
                    modelPicker(L.t("vision_model"), selection: $settings.visionModel, options: textModels)
                    modelPicker(L.t("image_model"), selection: $settings.imageModel, options: imageModels)
                    modelPicker(L.t("audio_model"), selection: $settings.audioModel, options: audioModels)
                    if settings.language == .de {
                        LabeledContent(L.t("voice")) {
                            Text(verbatim: SpeechSynthesizer.systemGermanVoiceName)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker(L.t("voice"), selection: $settings.ttsVoice) {
                            Text(verbatim: "👨 " + L.t("voice_male")).tag("daniel")
                            Text(verbatim: "👩 " + L.t("voice_female")).tag("hannah")
                        }
                    }
                    busyButton(title: L.t("load_models"),
                               busyTitle: L.t("loading_models"),
                               busy: loadingModels,
                               symbol: "arrow.clockwise",
                               enabled: settings.isConfigured) {
                        Task { await loadModels() }
                    }
                } header: {
                    Text(L.t("models"))
                } footer: {
                    Text((settings.availableModels.isEmpty
                          ? L.t("models_footer_empty")
                          : L.n("models_footer_count", settings.availableModels.count)) + " " + L.t("image_mode_hint"))
                }

                Section {
                    usageRow(L.t("storage_images"), "photo", usageDetail)
                    usageRow(L.t("storage_history"), "text.bubble", historyDetail)
                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Label(L.t("delete_all"), systemImage: "trash")
                    }
                    .disabled(cleaner.usage.conversations < 1)
                } header: {
                    Text(L.t("storage"))
                } footer: {
                    Text(L.t("fresh_start_note"))
                }

                Section {
                    busyButton(title: L.t("test_connection"),
                               busyTitle: L.t("testing"),
                               busy: testing,
                               symbol: nil,
                               enabled: settings.isConfigured) {
                        Task { await testConnection() }
                    }
                    if let r = testResult {
                        Text(r).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .id(settings.language)
            .environment(\.locale, settings.language.locale)
            .navigationTitle(L.t("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await cleaner.refreshUsage()
                if settings.availableModels.isEmpty && settings.isConfigured {
                    await loadModels()
                }
            }
            .onChange(of: settings.baseURL) { _, new in
                if AppSettings.knownEndpoints.contains(where: { $0.url == new }) {
                    Task { await loadModels() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("done")) { AppSettings.flushKeySave(); dismiss() }
                }
            }
            .alert(L.t("delete_all_title"), isPresented: $confirmDeleteAll) {
                Button(L.t("delete_all"), role: .destructive) { cleaner.deleteAllConversations() }
                Button(L.t("cancel"), role: .cancel) {}
            } message: {
                Text(L.fmt2("delete_all_body", String(cleaner.usage.conversations), deleteAllImagesText))
            }
        }
    }

    private func usageRow(_ title: String, _ symbol: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value).foregroundStyle(Color(.secondaryLabel))
        }
    }

    private var usageDetail: String {
        "\(cleaner.usage.imageFiles) · \(cleaner.usage.imageBytesText)"
    }

    private var historyDetail: String {
        "\(cleaner.usage.conversations) \(L.t("conversations_word")) · \(cleaner.usage.messages) \(L.t("messages_word"))"
    }

    private var deleteAllImagesText: String {
        "\(cleaner.usage.imageFiles) \(L.t("images_word")) (\(cleaner.usage.imageBytesText))"
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

    private func busyButton(title: String, busyTitle: String, busy: Bool,
                            symbol: String?, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
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

    @MainActor private func loadModels() async {
        AppSettings.flushKeySave()
        loadingModels = true
        testResult = nil
        defer { loadingModels = false }
        do {
            let models = try await QwenAPI.fetchModels(baseURL: settings.baseURL, key: settings.apiKey)
            settings.availableModels = models
            let text = ModelFilter.textCandidates(models)
            ensureSelection(\.chatModel, valid: models, fallback: text)
            ensureSelection(\.visionModel, valid: text, fallback: text)
            let images = ModelFilter.imageCandidates(models)
            ensureSelection(\.imageModel, valid: images, fallback: images)
            let audio = ModelFilter.audioCandidates(models)
            ensureSelection(\.audioModel, valid: audio, fallback: audio)
        } catch {
            testResult = L.t("models_error") + L.friendlyError(error.localizedDescription).message
        }
    }

    private func ensureSelection(_ keyPath: ReferenceWritableKeyPath<AppSettings, String>,
                                 valid: [String], fallback: [String]) {
        if !valid.contains(settings[keyPath: keyPath]), let first = fallback.first {
            settings[keyPath: keyPath] = first
        }
    }

    @MainActor private func testConnection() async {
        AppSettings.flushKeySave()
        testing = true
        testResult = nil
        defer { testing = false }
        let msg = ChatMessage(role: .user, text: L.t("test_prompt"))
        guard let req = try? QwenAPI.makeRequest(baseURL: settings.baseURL, key: settings.apiKey,
                                                 model: settings.chatModel, messages: [msg],
                                                 imageData: [], stream: true) else {
            testResult = L.t("invalid_url")
            return
        }
        do {
            var got = ""
            for try await chunk in QwenAPI.streamText(req: req) { got += chunk }
            testResult = got.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? L.t("connected_empty") : L.t("answered") + String(got.prefix(40))
        } catch {
            let e = L.friendlyError(error.localizedDescription, model: settings.chatModel)
            testResult = "✖ " + e.message + (e.detail.isEmpty ? "" : " (\(e.detail))")
        }
    }
}
