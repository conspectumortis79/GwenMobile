import GwenMobileKit
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case de
    case en
    case es
    case fr

    var id: String { rawValue }
    var flag: String {
        switch self {
        case .de: return "🇩🇪"
        case .en: return "🇬🇧"
        case .es: return "🇪🇸"
        case .fr: return "🇫🇷"
        }
    }
    var label: String {
        switch self {
        case .de: return "Deutsch"
        case .en: return "English"
        case .es: return "Español"
        case .fr: return "Français"
        }
    }
    var locale: Locale {
        switch self {
        case .de: return Locale(identifier: "de_DE")
        case .en: return Locale(identifier: "en_US")
        case .es: return Locale(identifier: "es_ES")
        case .fr: return Locale(identifier: "fr_FR")
        }
    }

    nonisolated var currencyCode: String {
        switch self {
        case .de, .es, .fr: return "EUR"
        case .en: return "USD"
        }
    }

    nonisolated static var deviceDefault: AppLanguage { deviceDefault(for: .current) }

    nonisolated static func deviceDefault(for locale: Locale) -> AppLanguage {
        switch locale.language.languageCode?.identifier {
        case "de": return .de
        case "es": return .es
        case "fr": return .fr
        default: return .en
        }
    }
}

enum L {
    private static let state = LockedValue(persistedLanguage())

    nonisolated static var lang: AppLanguage { state.current }

    nonisolated static func persistedLanguage(defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: SettingsKey.language) ?? "")
            ?? .deviceDefault
    }

    nonisolated static func apply(_ language: AppLanguage) { state.set(language) }

    nonisolated static func t(_ key: String) -> String {
        strings[key]?[lang] ?? key
    }

    nonisolated static func fmt(_ key: String, _ arg: String) -> String {
        (strings[key]?[lang] ?? key).replacingOccurrences(of: "%@", with: arg)
    }

    nonisolated static func fmt2(_ key: String, _ first: String, _ second: String) -> String {
        let parts = (strings[key]?[lang] ?? key).components(separatedBy: "%@")
        guard parts.count == 3 else { return parts.joined(separator: "%@") }
        return parts[0] + first + parts[1] + second + parts[2]
    }

    nonisolated static func n(_ key: String, _ count: Int) -> String {
        t(key).replacingOccurrences(of: "%d", with: String(count))
    }

    nonisolated static func counted(_ count: Int, one: String, many: String) -> String {
        count == 1 ? t(one) : n(many, count)
    }

    nonisolated static var dayFormat: String {
        switch lang {
        case .de: return "d. MMMM yyyy"
        case .en: return "MMMM d, yyyy"
        case .es: return "d 'de' MMMM 'de' yyyy"
        case .fr: return "d MMMM yyyy"
        }
    }
    nonisolated static var timeFormat: String {
        switch lang {
        case .de, .es, .fr: return "HH:mm"
        case .en: return "h:mm a"
        }
    }
    nonisolated static var calStartFormat: String {
        switch lang {
        case .de: return "E, d. MMM yyyy HH:mm"
        case .en: return "EEE, MMM d, yyyy h:mm a"
        case .es: return "E, d MMM yyyy HH:mm"
        case .fr: return "E d MMM yyyy HH:mm"
        }
    }
    nonisolated static var calChipFormat: String {
        switch lang {
        case .de, .es, .fr: return "E HH:mm"
        case .en: return "E h:mm a"
        }
    }

    struct FriendlyError: Equatable {
        var message: String
        var detail: String
        var openSettings: Bool
    }

    nonisolated static func friendlyError(_ raw: String, model: String? = nil, status: Int? = nil) -> FriendlyError {
        let low = raw.lowercased()
        let detail = detailLine(raw, status: status)
        func fe(_ key: String, settings: Bool = false) -> FriendlyError {
            FriendlyError(message: t(key), detail: detail, openSettings: settings)
        }
        if low.contains("exceeded maximum duration") { return fe("asr_too_long") }
        if status == 401 || status == 403 || low.contains("invalid_api_key") || low.contains("invalidapikey")
            || low.contains("invalid api-key") || low.contains("invalid api key") {
            return fe("err_bad_key", settings: true)
        }
        if low.contains("model_not_found") || low.contains("model not exist") || low.contains("model not found") {
            return FriendlyError(message: fmt("err_model_gone", model ?? "?"), detail: detail, openSettings: true)
        }
        if status == 402 || low.contains("available credits") || low.contains("insufficient balance")
            || low.contains("insufficient credit") || low.contains("arrearage") || low.contains("insufficient_quota") {
            return fe("err_no_credit", settings: true)
        }
        if status == 429 || low.contains("throttling") || low.contains("rate limit")
            || low.contains("quota") || low.contains("too many requests") {
            return fe("err_rate_limited")
        }
        if low.contains("tls error") || low.contains("secure connection")
            || low.contains("ssl") || low.contains("connection reset") {
            return fe("net_tls_blocked")
        }
        if low.contains("could not be found") || low.contains("network connection")
            || low.contains("not connected to the internet") || low.contains("wifi appears to be turned off")
            || low.contains("a server with the specified hostname") || low.contains("offline")
            || low.contains("netzwerk") || low.contains("verbindung zum server") {
            return fe("net_error")
        }
        if low.contains("authorized to record") || low.contains("!rec")
            || (low.contains("permission") && (low.contains("microphone") || low.contains("mic"))) {
            return fe("mic_denied")
        }
        return FriendlyError(message: raw, detail: "", openSettings: false)
    }

    private static func detailLine(_ raw: String, status: Int?) -> String {
        var head = String(raw.prefix { $0 != ":" })
        head = head.trimmed
        if head.count > 60 { head = String(head.prefix(60)) + "…" }
        if head.isEmpty { return status.map { "HTTP \($0)" } ?? "" }
        if let s = status { return "\(head) · HTTP \(s)" }
        return head
    }

    nonisolated static var defaultTitle: String { t("new_conversation") }

    static var defaultTitles: Set<String> {
        Set(L10nTable.values.filter { $0.key == "new_conversation" }.flatMap { $0.value.values })
    }

    static let strings: [String: [AppLanguage: String]] = L10nTable.values
}
