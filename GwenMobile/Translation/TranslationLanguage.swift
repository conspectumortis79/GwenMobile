import GwenMobileKit
import Foundation

enum TranslationFold {
    private static let spelledOut: [(String, String)] = [("ae", "a"), ("oe", "o"), ("ue", "u"), ("ss", "s")]

    static func of(_ text: String) -> String {
        var out = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for (from, to) in spelledOut {
            out = out.replacingOccurrences(of: from, with: to)
        }
        return out
    }
}

struct TranslationLanguage: Identifiable, Hashable, Sendable {
    let code: String

    var id: String { code }

    var language: Locale.Language { Locale.Language(identifier: code) }

    func name(for appLanguage: AppLanguage) -> String {
        let locale = appLanguage.locale
        let base = locale.localizedString(forLanguageCode: language.languageCode?.identifier ?? "") ?? code
        guard code.contains("-"), let script = language.script?.identifier else { return base }
        return "\(base) (\(locale.localizedString(forScriptCode: script) ?? script))"
    }
}

enum TranslationLanguages {
    static let all: [TranslationLanguage] = [
        TranslationLanguage(code: "ar"),
        TranslationLanguage(code: "bg"),
        TranslationLanguage(code: "bn"),
        TranslationLanguage(code: "ca"),
        TranslationLanguage(code: "cs"),
        TranslationLanguage(code: "da"),
        TranslationLanguage(code: "de"),
        TranslationLanguage(code: "el"),
        TranslationLanguage(code: "en"),
        TranslationLanguage(code: "es"),
        TranslationLanguage(code: "et"),
        TranslationLanguage(code: "fa"),
        TranslationLanguage(code: "fi"),
        TranslationLanguage(code: "fr"),
        TranslationLanguage(code: "ga"),
        TranslationLanguage(code: "he"),
        TranslationLanguage(code: "hi"),
        TranslationLanguage(code: "hr"),
        TranslationLanguage(code: "hu"),
        TranslationLanguage(code: "id"),
        TranslationLanguage(code: "it"),
        TranslationLanguage(code: "ja"),
        TranslationLanguage(code: "ko"),
        TranslationLanguage(code: "ms"),
        TranslationLanguage(code: "nb"),
        TranslationLanguage(code: "nl"),
        TranslationLanguage(code: "pl"),
        TranslationLanguage(code: "pt"),
        TranslationLanguage(code: "ro"),
        TranslationLanguage(code: "ru"),
        TranslationLanguage(code: "sk"),
        TranslationLanguage(code: "sl"),
        TranslationLanguage(code: "sr"),
        TranslationLanguage(code: "sv"),
        TranslationLanguage(code: "th"),
        TranslationLanguage(code: "tr"),
        TranslationLanguage(code: "uk"),
        TranslationLanguage(code: "vi"),
        TranslationLanguage(code: "zh-Hans"),
        TranslationLanguage(code: "zh-Hant")
    ]

    static let codes: [String] = all.map(\.code)

    static func withCode(_ code: String?) -> TranslationLanguage? {
        guard let code else { return nil }
        let wanted = TranslationFold.of(code)
        guard !wanted.isEmpty else { return nil }
        let folded = all.map { ($0, TranslationFold.of($0.code)) }
        if let exact = folded.first(where: { $0.1 == wanted }) { return exact.0 }
        let primary = String(wanted.prefix { $0 != "-" })
        if let shorter = folded.first(where: { wanted.hasPrefix($0.1 + "-") }) { return shorter.0 }
        return folded.first(where: { primary.count >= 2 && $0.1.hasPrefix(primary + "-") })?.0
    }

    static func named(_ code: String) -> String {
        withCode(code)?.name(for: L.lang) ?? code
    }

    static func pairLabel(from source: String?, to target: String) -> String {
        let sourceName = withCode(source)?.name(for: L.lang) ?? L.t("translate_detected")
        return "\(sourceName) → \(named(target))"
    }

    static var fallbackTarget: String {
        switch L.lang {
        case .de: return "en"
        case .en: return "de"
        case .es, .fr: return "en"
        }
    }
}
