import Foundation

struct VoiceSettings: Equatable, Codable {
    var speakAnswers = false
    var outputVoice = VoiceOption.systemDefaultID
    var listenMode = false
    var conversationMode = false
    var onlyMyVoice = false
    var speakerSensitivity = SpeakerSensitivity.normal
    var wakeWord = ""
    var stopWord = ""
    var cancelWord = ""
    var newChatWord = ""
    var listenOffWord = ""
    var deleteHistoryWord = ""
    var sentSound = ""
    var dictationLimitSeconds = AppSettings.defaultDictationLimit
    var dictationSilenceSeconds = AppSettings.defaultDictationSilence

    static func load(from defaults: UserDefaults = .standard) -> VoiceSettings {
        let d = defaults
        var settings = VoiceSettings()
        settings.speakAnswers = d.bool(forKey: SettingsKey.speakAnswers)
        settings.outputVoice = d.string(forKey: SettingsKey.outputVoice)
            ?? d.string(forKey: SettingsKey.legacyTTSVoice)
            ?? VoiceOption.systemDefaultID
        settings.listenMode = d.bool(forKey: SettingsKey.listenMode)
        settings.conversationMode = d.bool(forKey: SettingsKey.conversationMode)
        settings.onlyMyVoice = d.bool(forKey: SettingsKey.onlyMyVoice)
        settings.speakerSensitivity = (d.object(forKey: SettingsKey.speakerSensitivity) as? Int)
            .flatMap(SpeakerSensitivity.init(rawValue:)) ?? .normal
        settings.wakeWord = d.string(forKey: SettingsKey.wakeWord) ?? ""
        settings.stopWord = d.string(forKey: SettingsKey.stopWord) ?? ""
        settings.cancelWord = d.string(forKey: SettingsKey.cancelWord) ?? ""
        settings.newChatWord = d.string(forKey: SettingsKey.newChatWord) ?? ""
        settings.listenOffWord = d.string(forKey: SettingsKey.listenOffWord) ?? ""
        settings.deleteHistoryWord = d.string(forKey: SettingsKey.deleteHistoryWord) ?? ""
        settings.sentSound = d.string(forKey: SettingsKey.sentSound) ?? ""
        settings.dictationLimitSeconds = AppSettings.validChoice(d.object(forKey: SettingsKey.dictationLimit) as? Int,
                                                                 choices: AppSettings.dictationLimitChoices,
                                                                 fallback: AppSettings.defaultDictationLimit)
        settings.dictationSilenceSeconds = AppSettings.validChoice(
            d.object(forKey: SettingsKey.dictationSilence) as? Int,
            choices: AppSettings.dictationSilenceChoices,
            fallback: AppSettings.defaultDictationSilence)
        return settings
    }

    func store(to defaults: UserDefaults = .standard) {
        let d = defaults
        d.set(speakAnswers, forKey: SettingsKey.speakAnswers)
        d.set(outputVoice, forKey: SettingsKey.outputVoice)
        d.set(listenMode, forKey: SettingsKey.listenMode)
        d.set(conversationMode, forKey: SettingsKey.conversationMode)
        d.set(onlyMyVoice, forKey: SettingsKey.onlyMyVoice)
        d.set(speakerSensitivity.rawValue, forKey: SettingsKey.speakerSensitivity)
        d.set(wakeWord, forKey: SettingsKey.wakeWord)
        d.set(stopWord, forKey: SettingsKey.stopWord)
        d.set(cancelWord, forKey: SettingsKey.cancelWord)
        d.set(newChatWord, forKey: SettingsKey.newChatWord)
        d.set(listenOffWord, forKey: SettingsKey.listenOffWord)
        d.set(deleteHistoryWord, forKey: SettingsKey.deleteHistoryWord)
        d.set(sentSound, forKey: SettingsKey.sentSound)
        d.set(dictationLimitSeconds, forKey: SettingsKey.dictationLimit)
        d.set(dictationSilenceSeconds, forKey: SettingsKey.dictationSilence)
    }

    var normalized: VoiceSettings {
        var settings = self
        settings.dictationLimitSeconds = AppSettings.validChoice(dictationLimitSeconds,
                                                                 choices: AppSettings.dictationLimitChoices,
                                                                 fallback: AppSettings.defaultDictationLimit)
        settings.dictationSilenceSeconds = AppSettings.validChoice(
            dictationSilenceSeconds,
            choices: AppSettings.dictationSilenceChoices,
            fallback: AppSettings.defaultDictationSilence)
        return settings
    }
}
