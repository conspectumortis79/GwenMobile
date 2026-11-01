@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import AVFoundation
import Combine
import SwiftUI

struct VoiceOutputSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var voices: [VoiceOption] = []
    @State private var personalVoiceStatus = AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus.notDetermined
    @State private var showPersonalVoiceInfo = false
    @State private var previewSynthesizer: AVSpeechSynthesizer?

    var body: some View {
        Group {
            Section {
                voicePicker
            } footer: {
                Text([L.t("speech_footer"), L.t("voice_footer")].joined(separator: " "))
            }
            personalVoiceSection
        }
        .task {
            loadVoices()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            loadVoices()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            loadVoices()
        }
        .alert(L.t("voice_personal_explain_title"), isPresented: $showPersonalVoiceInfo) {
            Button(L.t("cancel"), role: .cancel) {}
            Button(L.t("voice_personal_continue")) {
                Task { await requestPersonalVoice() }
            }
        } message: {
            Text(L.t("voice_personal_explain_message"))
        }
        .onDisappear {
            previewSynthesizer?.stopSpeaking(at: .immediate)
            previewSynthesizer = nil
        }
    }

    private var voiceOptions: [VoiceOption] {
        if voices.contains(where: { $0.id == settings.voice.outputVoice })
            || settings.voice.outputVoice == VoiceOption.systemDefaultID {
            return voices
        }
        if let voice = AVSpeechSynthesisVoice(identifier: settings.voice.outputVoice) {
            return voices + [VoiceOption(id: voice.identifier, name: voice.name, language: voice.language,
                                         isPersonal: voice.voiceTraits.contains(.isPersonalVoice))]
        }
        return voices + [VoiceOption(id: settings.voice.outputVoice, name: L.t("voice_unavailable"),
                                     language: "")]
    }

    private var voicePicker: some View {
        let home = VoiceCatalog.defaultLanguage(for: settings.language)
        return Picker(L.t("voice"), selection: $settings.voice.outputVoice) {
            Text(VoiceCatalog.defaultLabel(for: settings.language))
                .tag(VoiceOption.systemDefaultID)
            ForEach(voiceOptions) { option in
                Text(verbatim: option.label(defaultLanguage: home)).tag(option.id)
            }
        }
    }

    private var personalVoices: [VoiceOption] {
        voices.filter(\.isPersonal)
    }

    private var selectedPersonalVoice: VoiceOption? {
        personalVoices.first { $0.id == settings.voice.outputVoice }
    }

    private var personalVoiceStatusText: String {
        switch personalVoiceStatus {
        case .authorized:
            return personalVoices.isEmpty
                ? L.t("voice_personal_status_missing")
                : L.t("voice_personal_status_ready")
        case .denied:
            return L.t("voice_personal_status_denied")
        case .notDetermined:
            return L.t("voice_personal_status_not_determined")
        case .unsupported:
            return L.t("voice_personal_status_unsupported")
        @unknown default:
            return L.t("voice_personal_status_unsupported")
        }
    }

    private var personalVoiceLanguageHint: String? {
        guard let selected = selectedPersonalVoice else { return nil }
        let home = String(VoiceCatalog.defaultLanguage(for: settings.language).prefix(2))
        guard !selected.language.hasPrefix(home) else { return nil }
        let voiceLanguage = L.lang.locale.localizedString(forIdentifier: selected.language)
            ?? selected.language
        return L.fmt2("voice_personal_language_hint", voiceLanguage, settings.language.label)
    }

    @ViewBuilder
    private var personalVoiceSection: some View {
        Section {
            LabeledContent(L.t("voice_personal_status")) {
                Text(personalVoiceStatusText)
                    .foregroundStyle(personalVoiceStatus == .denied ? Color.red : Color.secondary)
            }
            switch personalVoiceStatus {
            case .authorized:
                authorizedPersonalVoiceRows
            case .notDetermined:
                Button {
                    showPersonalVoiceInfo = true
                } label: {
                    Label(L.t("voice_personal_enable"), systemImage: "person.wave.2")
                }
            case .denied:
                Text(L.t("voice_personal_denied_hint"))
                    .scaledFont(12)
                    .foregroundStyle(Color(.secondaryLabel))
            case .unsupported:
                Text(L.t("voice_personal_unsupported_hint"))
                    .scaledFont(12)
                    .foregroundStyle(Color(.secondaryLabel))
            @unknown default:
                EmptyView()
            }
            if personalVoiceStatus != .unsupported {
                Button {
                    loadVoices()
                } label: {
                    Label(L.t("voice_personal_refresh"), systemImage: "arrow.clockwise")
                }
            }
        } header: {
            Text(L.t("voice_personal_section"))
        } footer: {
            Text(L.t("voice_personal_footer"))
        }
    }

    @ViewBuilder
    private var authorizedPersonalVoiceRows: some View {
        if personalVoices.isEmpty {
            Text(L.t("voice_personal_steps"))
                .scaledFont(12)
                .foregroundStyle(Color(.secondaryLabel))
            Text(L.t("voice_personal_missing_hint"))
                .scaledFont(12)
                .foregroundStyle(Color(.secondaryLabel))
        } else if let selected = selectedPersonalVoice {
            LabeledContent(L.t("voice_personal_selected")) {
                Text(verbatim: selected.name)
            }
            if let hint = personalVoiceLanguageHint {
                Text(hint)
                    .scaledFont(12)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Button {
                preview(selected)
            } label: {
                Label(L.t("voice_personal_preview"), systemImage: "play.circle")
            }
        } else {
            Text(L.t("voice_personal_ready_hint"))
                .scaledFont(12)
                .foregroundStyle(Color(.secondaryLabel))
            Button {
                selectFirstPersonalVoice()
            } label: {
                Label(L.t("voice_personal_enable"), systemImage: "person.wave.2")
            }
        }
    }

    @MainActor private func preview(_ option: VoiceOption) {
        guard let voice = AVSpeechSynthesisVoice(identifier: option.id) else { return }
        previewSynthesizer?.stopSpeaking(at: .immediate)
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: L.t("voice_personal_preview_text"))
        utterance.voice = voice
        utterance.rate = SpeechSynthesizer.localRate
        previewSynthesizer = synthesizer
        synthesizer.speak(utterance)
    }

    @MainActor private func loadVoices(status: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus? = nil) {
        voices = VoiceCatalog.options(for: settings.language)
        personalVoiceStatus = status ?? PersonalVoiceAccess.status
        flowMark("STIMME personal status=\(personalVoiceStatus.rawValue) "
                 + "gesamt=\(voices.count) personal=\(personalVoices.count)")
    }

    @MainActor private func selectFirstPersonalVoice() {
        guard let first = personalVoices.first else { return }
        settings.voice.outputVoice = first.id
    }

    @MainActor private func requestPersonalVoice() async {
        let status = await PersonalVoiceAccess.request()
        personalVoiceStatus = status
        loadVoices(status: status)
        guard status == .authorized else { return }
        guard !voices.contains(where: { $0.id == settings.voice.outputVoice && $0.isPersonal }) else { return }
        selectFirstPersonalVoice()
    }
}
