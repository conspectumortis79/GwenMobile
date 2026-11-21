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
    var microphoneSensitivity = SpeechLevelBoost.standardSensitivity

    static func load(from defaults: UserDefaults = .standard) -> VoiceSettings {
        var settings = VoiceSettings()
        settings.outputVoice = SettingsDefaults.storedString(defaults, SettingsKey.outputVoice)
            ?? SettingsDefaults.storedString(defaults, SettingsKey.legacyTTSVoice)
            ?? VoiceOption.systemDefaultID
        settings.speakAnswers = SettingsDefaults.flag(defaults, SettingsKey.speakAnswers)
        settings.listenMode = SettingsDefaults.flag(defaults, SettingsKey.listenMode)
        settings.conversationMode = SettingsDefaults.flag(defaults, SettingsKey.conversationMode)
        settings.onlyMyVoice = SettingsDefaults.flag(defaults, SettingsKey.onlyMyVoice)
        settings.speakerSensitivity = SettingsDefaults.rawValue(defaults, SettingsKey.speakerSensitivity, .normal)
        settings.wakeWord = SettingsDefaults.string(defaults, SettingsKey.wakeWord)
        settings.stopWord = SettingsDefaults.string(defaults, SettingsKey.stopWord)
        settings.cancelWord = SettingsDefaults.string(defaults, SettingsKey.cancelWord)
        settings.newChatWord = SettingsDefaults.string(defaults, SettingsKey.newChatWord)
        settings.listenOffWord = SettingsDefaults.string(defaults, SettingsKey.listenOffWord)
        settings.deleteHistoryWord = SettingsDefaults.string(defaults, SettingsKey.deleteHistoryWord)
        settings.sentSound = SettingsDefaults.string(defaults, SettingsKey.sentSound)
        settings.dictationLimitSeconds = SettingsDefaults.validChoice(defaults, SettingsKey.dictationLimit,
                                                                      AppSettings.dictationLimitChoices,
                                                                      AppSettings.defaultDictationLimit)
        settings.dictationSilenceSeconds = SettingsDefaults.validChoice(defaults, SettingsKey.dictationSilence,
                                                                        AppSettings.dictationSilenceChoices,
                                                                        AppSettings.defaultDictationSilence)
        settings.microphoneSensitivity = SpeechLevelBoost.clampedSensitivity(
            SettingsDefaults.int(defaults, SettingsKey.microphoneSensitivity,
                                 SpeechLevelBoost.standardSensitivity))
        return settings
    }

    func store(to defaults: UserDefaults = .standard) {
        defaults.set(speakAnswers, forKey: SettingsKey.speakAnswers)
        defaults.set(outputVoice, forKey: SettingsKey.outputVoice)
        defaults.set(listenMode, forKey: SettingsKey.listenMode)
        defaults.set(conversationMode, forKey: SettingsKey.conversationMode)
        defaults.set(onlyMyVoice, forKey: SettingsKey.onlyMyVoice)
        defaults.set(speakerSensitivity.rawValue, forKey: SettingsKey.speakerSensitivity)
        defaults.set(wakeWord, forKey: SettingsKey.wakeWord)
        defaults.set(stopWord, forKey: SettingsKey.stopWord)
        defaults.set(cancelWord, forKey: SettingsKey.cancelWord)
        defaults.set(newChatWord, forKey: SettingsKey.newChatWord)
        defaults.set(listenOffWord, forKey: SettingsKey.listenOffWord)
        defaults.set(deleteHistoryWord, forKey: SettingsKey.deleteHistoryWord)
        defaults.set(sentSound, forKey: SettingsKey.sentSound)
        defaults.set(dictationLimitSeconds, forKey: SettingsKey.dictationLimit)
        defaults.set(dictationSilenceSeconds, forKey: SettingsKey.dictationSilence)
        defaults.set(microphoneSensitivity, forKey: SettingsKey.microphoneSensitivity)
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
        settings.microphoneSensitivity = SpeechLevelBoost.clampedSensitivity(microphoneSensitivity)
        return settings
    }
}
