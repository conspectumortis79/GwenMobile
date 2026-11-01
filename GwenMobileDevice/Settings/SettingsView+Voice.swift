@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

extension SettingsView {
    var voiceControlSection: some View {
        Section {
            Toggle(isOn: conversationBinding) {
                Text(L.t("conversation_mode")).scaledFont(15)
            }
            Text(L.t("conversation_mode_footer"))
                .scaledFont(12)
                .foregroundStyle(Color(.secondaryLabel))
            Toggle(isOn: onlyMyVoiceBinding) {
                Text(L.t("speaker_only_me")).scaledFont(15)
            }
            Button {
                showSpeakerEnrollment = true
            } label: {
                HStack {
                    Text(L.t("speaker_profile"))
                    Spacer()
                    Text(speakerProfile.map { L.counted($0.sampleCount, one: "speaker_profile_ready_one",
                                                             many: "speaker_profile_ready") }
                         ?? L.t("speaker_profile_missing"))
                        .foregroundStyle(Color(.secondaryLabel))
                    Image(systemName: "chevron.right")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)
            if settings.voice.onlyMyVoice {
                Picker(L.t("speaker_sensitivity"), selection: $settings.voice.speakerSensitivity) {
                    ForEach(SpeakerSensitivity.allCases) { level in
                        Text(L.t(level.key)).tag(level)
                    }
                }
            }
            Text(L.t("speaker_only_me_footer"))
                .scaledFont(12)
                .foregroundStyle(Color(.secondaryLabel))
            Toggle(isOn: $settings.voice.listenMode) {
                Text(L.t("listen_mode")).scaledFont(15)
            }
            voiceWordField(L.t("wake_word"), text: $settings.voice.wakeWord, fallback: VoiceWords.wakeKey)
            voiceWordField(L.t("stop_word"), text: $settings.voice.stopWord, fallback: VoiceWords.stopKey)
            voiceWordField(L.t("cancel_word"), text: $settings.voice.cancelWord, fallback: VoiceWords.cancelKey)
            voiceWordField(L.t("new_chat_word"), text: $settings.voice.newChatWord, fallback: VoiceWords.newChatKey)
            voiceWordField(L.t("delete_history_word"), text: $settings.voice.deleteHistoryWord,
                           fallback: VoiceWords.deleteHistoryKey)
            voiceWordField(L.t("listen_off_word"), text: $settings.voice.listenOffWord, fallback: VoiceWords.listenOffKey)
            dictationLimitRow
            dictationSilenceRow
            cueSoundRow(L.t("sent_sound"), selection: $settings.voice.sentSound, tone: .sent)
        } header: {
            Text(L.t("voice_control"))
        } footer: {
            Text(L.t("voice_control_footer"))
        }
    }

    private var onlyMyVoiceBinding: Binding<Bool> {
        Binding(get: { settings.voice.onlyMyVoice },
                set: { on in
                    if on, SpeakerProfileStore.shared.load() == nil {
                        showSpeakerEnrollment = true
                        return
                    }
                    settings.voice.onlyMyVoice = on
                })
    }

    private var conversationBinding: Binding<Bool> {
        Binding(get: { settings.voice.conversationMode },
                set: { on in
                    settings.voice.conversationMode = on
                    if on {
                        settings.voice.listenMode = false
                    }
                })
    }

    func cueSoundRow(_ title: String, selection: Binding<String>, tone: ChimeTone) -> some View {
        NavigationLink {
            CueSoundPicker(title: title, selection: selection, tone: tone)
        } label: {
            LabeledContent(title) {
                Text(verbatim: CueSoundLabel.name(of: selection.wrappedValue))
            }
        }
    }

    func voiceWordField(_ title: String, text: Binding<String>, fallback: String) -> some View {
        LabeledContent(title) {
            TextField(L.t(fallback), text: text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    var dictationLimitRow: some View {
        Picker(L.t("dictation_limit"), selection: $settings.voice.dictationLimitSeconds) {
            ForEach(AppSettings.dictationLimitChoices, id: \.self) { seconds in
                Text(verbatim: "\(seconds / 60) min").tag(seconds)
            }
        }
    }

    var dictationSilenceRow: some View {
        Picker(L.t("dictation_silence"), selection: $settings.voice.dictationSilenceSeconds) {
            ForEach(AppSettings.dictationSilenceChoices, id: \.self) { seconds in
                Text(verbatim: "\(seconds) s").tag(seconds)
            }
        }
    }

}
