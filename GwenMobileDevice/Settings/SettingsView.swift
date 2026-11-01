@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import AppIntents
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var cleaner: HistoryCleaner
    @Environment(\.dismiss) private var dismiss
    @State private var path: [SettingsCategory] = []
    @State var testResult: String?
    @State var confirmDeleteAll = false
    @State var testing = false
    @State var balance: String?
    @State var testStream: Task<Void, Never>?
    @State var showMemory = false
    @State var showSpeakerEnrollment = false
    @State var speakerProfile: SpeakerProfile?
    @State var confirmDeleteMemory = false
    @State var memoryCount = 0
    @State var showPriceWatch = false
    @State var priceWatchCount = 0
    var chatRunner: @MainActor (URLRequest, @escaping @MainActor (String) -> Void) async throws -> String = {
        request, onChunk in
        try await ChatRunner.shared.run(request, onChunk: onChunk)
    }

    init(initialCategory: SettingsCategory? = nil) {
        _path = State(initialValue: initialCategory.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            rootForm
                .navigationDestination(for: SettingsCategory.self) { category in
                    SettingsCategoryView(owner: self, category: category)
                }
        }
        .windowAppearance()
        .task {
            memoryCount = await store.memory.count()
            priceWatchCount = await store.watches.count()
            await cleaner.refreshUsage()
        }
        .onChange(of: settings.connectionIdentity) { _, _ in
            balance = nil
            testResult = nil
        }
        .onChange(of: showMemory) { _, open in
            guard !open else { return }
            Task { memoryCount = await store.memory.count() }
        }
        .onChange(of: showSpeakerEnrollment) { _, open in
            guard !open else { return }
            speakerProfile = SpeakerProfileStore.shared.load()
            if settings.voice.onlyMyVoice, speakerProfile == nil {
                settings.voice.onlyMyVoice = false
            }
        }
        .onChange(of: showPriceWatch) { _, open in
            guard !open else { return }
            Task { priceWatchCount = await store.watches.count() }
        }
        .onAppear { speakerProfile = SpeakerProfileStore.shared.load() }
        .onDisappear { abandonConnectionTest() }
        .deleteAllConfirmation(cleaner: cleaner, isPresented: $confirmDeleteAll)
        .sheet(isPresented: $showMemory) {
            NavigationStack { MemoryView() }
        }
        .sheet(isPresented: $showSpeakerEnrollment) {
            SpeakerEnrollmentView()
        }
        .sheet(isPresented: $showPriceWatch) {
            NavigationStack { PriceWatchView() }
        }
    }

    private var rootForm: some View {
        Form {
            Section {
                ForEach(SettingsCategory.allCases) { category in
                    NavigationLink(value: category) {
                        SettingsCategoryRow(category: category, detail: summary(for: category))
                    }
                }
            } header: {
                Text(L.t("settings_configuration"))
            }
            testSection
        }
        .id(settings.language)
        .environment(\.locale, settings.language.locale)
        .navigationTitle(L.t("settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                doneButton
            }
        }
    }

    var doneButton: some View {
        Button(L.t("done"), action: TapProbe.action({ AppSettings.flushKeySave(); dismiss() }))
    }

    @ViewBuilder
    func categorySections(_ category: SettingsCategory) -> some View {
        switch category {
        case .ai:
            providerSummarySection
            connectionSection
            ModelsSettingsView(testResult: $testResult)
            researchSection
        case .voice:
            VoiceOutputSettingsView()
            voiceControlSection
        case .language:
            languageSection
            appearanceSection
        case .data:
            memorySection
            filesSection
            storageSection
        case .services:
            MusicSettingsSection(settings: settings)
            DayBriefingSettingsSection(settings: settings)
            priceWatchSection
            siriSection
        case .help:
            helpSection
        }
    }

    private func summary(for category: SettingsCategory) -> String {
        switch category {
        case .ai: return aiSummary
        case .voice: return voiceSummary
        case .language: return "\(settings.language.label) · \(settings.appearance.label)"
        case .data: return dataSummary
        case .services:
            return [L.t("music_section"), L.t("brief_settings"),
                    L.t("price_watch_settings_row")].joined(separator: " · ")
        case .help: return L.t("help_attach_row")
        }
    }

    private var aiSummary: String {
        let model = settings.chatModel.isEmpty ? L.t("app_status_value_not_configured") : settings.chatModel
        return "\(settings.descriptor.title) · \(model)"
    }

    private var voiceSummary: String {
        let listening = settings.voice.listenMode
            ? L.t("settings_listening_on")
            : L.t("settings_listening_off")
        return "\(voiceName) · \(listening)"
    }

    private var voiceName: String {
        if settings.voice.outputVoice == VoiceOption.systemDefaultID {
            return VoiceCatalog.defaultLabel(for: settings.language)
        }
        let home = VoiceCatalog.defaultLanguage(for: settings.language)
        if let option = VoiceCatalog.options(for: settings.language)
            .first(where: { $0.id == settings.voice.outputVoice }) {
            return option.label(defaultLanguage: home)
        }
        return L.t("voice_unavailable")
    }

    private var dataSummary: String {
        "\(memoryCountLabel) · \(storageTotalText)"
    }

    private var storageTotalText: String {
        let bytes = StorageUsage.sum([cleaner.usage.imageBytes, cleaner.usage.documentBytes,
                                      cleaner.usage.exportBytes])
        return StorageUsage.bytesText(bytes)
    }

    private var providerSummarySection: some View {
        Section {
            NavigationLink {
                ProviderSelectionView()
            } label: {
                HStack(spacing: 12) {
                    ProviderGlyphView(glyph: settings.descriptor.glyph)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: settings.descriptor.title)
                            .foregroundStyle(Color.primary)
                        Text(verbatim: settings.descriptor.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
            }
        } header: {
            Text(L.t("provider_section"))
        } footer: {
            Text(L.t("provider_footer"))
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: $settings.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(verbatim: "\(lang.flag)  \(lang.label)").tag(lang)
                }
            } label: {
                Label(L.t("language"), systemImage: "globe")
            }
            #if targetEnvironment(macCatalyst)
            Toggle(isOn: Binding(get: { MacLoginItem.isEnabled }, set: { wanted in
                if let problem = MacLoginItem.setEnabled(wanted) {
                    flowLog.error("MAC autostart abgelehnt \(problem, privacy: .public)")
                }
            })) {
                Label(L.t("mac_autostart"), systemImage: "power")
            }
            #endif
        } header: {
            Text(L.t("language"))
        } footer: {
            Text(L.t("language_footer"))
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(selection: $settings.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(verbatim: appearance.label).tag(appearance)
                }
            } label: {
                Label(L.t("appearance"), systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.segmented)
        } header: {
            Text(L.t("appearance"))
        } footer: {
            Text(L.t("appearance_footer"))
        }
    }

    private var siriSection: some View {
        Section {
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
        } header: {
            Text(L.t("siri_own_command"))
        } footer: {
            Text(L.t("siri_own_steps"))
        }
    }

    private var helpSection: some View {
        Section {
            Button(action: TapProbe.action({ HelpRequests.shared.ask() })) {
                HStack(spacing: 12) {
                    Label(L.t("help_settings_row"), systemImage: "questionmark.circle")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .foregroundStyle(Color.primary)
        } header: {
            Text(L.t("help_title"))
        } footer: {
            Text(L.t("help_settings_footer"))
        }
    }

    private var testSection: some View {
        Section {
            SettingsBusyButton(title: L.t("test_connection"),
                               busyTitle: L.t("testing"),
                               busy: testing,
                               symbol: nil,
                               enabled: settings.isConfigured, action: TapProbe.action({
                runConnectionTest()
            }))
            if let r = testResult {
                Text(r).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text(L.t("settings_connection"))
        }
    }
}
