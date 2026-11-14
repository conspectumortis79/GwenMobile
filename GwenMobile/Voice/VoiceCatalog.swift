import GwenMobileKit
import AVFoundation

struct VoiceOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    let isPersonal: Bool

    static let systemDefaultID = ""

    init(id: String, name: String, language: String, isPersonal: Bool = false) {
        self.id = id
        self.name = name
        self.language = language
        self.isPersonal = isPersonal
    }

    func label(defaultLanguage: String) -> String {
        if isPersonal {
            let label = L.fmt("voice_personal_label", name)
            guard language != defaultLanguage, let region = VoiceOption.regionName(of: language) else {
                return label
            }
            return "\(label) (\(region))"
        }
        guard language != defaultLanguage, let region = VoiceOption.regionName(of: language) else { return name }
        return "\(name) (\(region))"
    }

    static func baseName(_ name: String) -> String {
        guard let open = name.firstIndex(of: "("), open > name.startIndex else { return name }
        return name[..<open].trimmingCharacters(in: .whitespaces)
    }

    static func regionName(of language: String) -> String? {
        guard let region = Locale(identifier: language).region?.identifier else { return nil }
        return Locale.current.localizedString(forRegionCode: region)
    }
}

enum VoiceCatalog {
    static func defaultLanguage(for language: AppLanguage) -> String {
        switch language {
        case .de: return "de-DE"
        case .en: return "en-US"
        case .es: return "es-ES"
        case .fr: return "fr-FR"
        }
    }

    static func defaultVoice(for language: AppLanguage) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: defaultLanguage(for: language))
    }

    static func defaultVoiceName(for language: AppLanguage) -> String {
        defaultVoice(for: language)?.name ?? language.label
    }

    static func defaultLabel(for language: AppLanguage) -> String {
        L.fmt("voice_default", VoiceOption.baseName(defaultVoiceName(for: language)))
    }

    static func options(for language: AppLanguage,
                        voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()) -> [VoiceOption] {
        options(for: language, from: voices.map(option))
    }

    static func options(for language: AppLanguage, from options: [VoiceOption]) -> [VoiceOption] {
        let code = defaultLanguage(for: language).prefix(2)
        let personal = options.filter(\.isPersonal)
        let system = options.filter { !$0.isPersonal && $0.language.hasPrefix(code) }
        return sorted(personal + system, defaultLanguage: defaultLanguage(for: language))
    }

    static func sorted(_ options: [VoiceOption], defaultLanguage: String) -> [VoiceOption] {
        options.sorted { lhs, rhs in
            if lhs.isPersonal != rhs.isPersonal { return lhs.isPersonal }
            let lhsHome = lhs.language == defaultLanguage
            let rhsHome = rhs.language == defaultLanguage
            if lhsHome != rhsHome { return lhsHome }
            if lhs.language != rhs.language { return lhs.language < rhs.language }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func isPersonalVoice(identifier: String) -> Bool {
        guard identifier != VoiceOption.systemDefaultID,
              let voice = AVSpeechSynthesisVoice(identifier: identifier) else { return false }
        return voice.voiceTraits.contains(.isPersonalVoice)
    }

    static func voice(identifier: String, language: AppLanguage) -> AVSpeechSynthesisVoice? {
        guard identifier != VoiceOption.systemDefaultID,
              let chosen = AVSpeechSynthesisVoice(identifier: identifier) else {
            return defaultVoice(for: language)
        }
        return chosen
    }

    private static func option(_ voice: AVSpeechSynthesisVoice) -> VoiceOption {
        VoiceOption(id: voice.identifier, name: voice.name, language: voice.language,
                    isPersonal: voice.voiceTraits.contains(.isPersonalVoice))
    }
}
