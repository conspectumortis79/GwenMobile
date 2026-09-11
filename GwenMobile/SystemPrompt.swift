import Foundation

enum SystemPrompt {
    static let dateLocale = "en_GB"
    static let dateFormat = "EEEE, yyyy-MM-dd"

    static func chat() -> String {
        var sysText = L.t("system_lang")
        sysText += "\n\nCurrent date: \(currentDate()). "
        sysText += "Treat any event dated after today as unknown to you."
        sysText += "\n\n" + L.t("format_hint")
        sysText += "\n\n" + L.t("web_search_prompt")
        return sysText
    }

    static func currentDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: dateLocale)
        formatter.dateFormat = dateFormat
        return formatter.string(from: Date())
    }
}
