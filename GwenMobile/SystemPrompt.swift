import Foundation

enum SystemPrompt {
    static func chat() -> String {
        var sysText = L.t("system_lang")
        sysText += "\n\nCurrent date: \(currentDate()). "
        sysText += "Treat any event dated after today as unknown to you."
        sysText += "\n\n" + L.t("format_hint")
        sysText += "\n\n" + L.t("web_search_prompt")
        sysText += "\n\n" + L.t("web_chart_prompt")
        return sysText
    }

    static func currentDate() -> String {
        Formatters.systemDate(Date())
    }
}
