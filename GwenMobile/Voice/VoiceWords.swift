import GwenMobileKit
import Foundation

enum VoiceWords {
    static let wakeKey = "voice_wake_default"
    static let stopKey = "voice_stop_default"
    static let cancelKey = "voice_cancel_default"
    static let newChatKey = "voice_new_chat_default"
    static let listenOffKey = "voice_listen_off_default"
    static let deleteHistoryKey = "voice_delete_history_default"

    static func effective(_ custom: String, defaultKey: String) -> String {
        let chosen = custom.trimmed
        return chosen.isEmpty ? L.t(defaultKey) : chosen
    }

    static func signals(wake: String, stop: String, cancel: String, newChat: String = "",
                        listenOff: String = "") -> VoiceSignals {
        VoiceSignals(wake: effective(wake, defaultKey: wakeKey), stop: effective(stop, defaultKey: stopKey),
                     cancel: effective(cancel, defaultKey: cancelKey),
                     newChat: effective(newChat, defaultKey: newChatKey),
                     listenOff: effective(listenOff, defaultKey: listenOffKey))
    }
}

extension AppSettings {
    var voiceSignals: VoiceSignals {
        VoiceWords.signals(wake: voice.wakeWord, stop: voice.stopWord, cancel: voice.cancelWord,
                           newChat: voice.newChatWord, listenOff: voice.listenOffWord)
    }
    var spokenWake: String { VoiceWords.effective(voice.wakeWord, defaultKey: VoiceWords.wakeKey) }
    var spokenStop: String { VoiceWords.effective(voice.stopWord, defaultKey: VoiceWords.stopKey) }
    var spokenCancel: String { VoiceWords.effective(voice.cancelWord, defaultKey: VoiceWords.cancelKey) }
    var spokenDeleteHistory: String {
        VoiceWords.effective(voice.deleteHistoryWord, defaultKey: VoiceWords.deleteHistoryKey)
    }
    var voiceTiming: VoiceTiming {
        VoiceTiming(silence: TimeInterval(voice.dictationSilenceSeconds),
                    nothingSaid: VoiceTiming.standard.nothingSaid,
                    maximum: TimeInterval(voice.dictationLimitSeconds))
    }
}
