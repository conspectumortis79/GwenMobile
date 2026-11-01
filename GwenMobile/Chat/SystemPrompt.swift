import GwenMobileKit
import Foundation

enum SystemPrompt {
    static func chat() -> String {
        greeting() + "\n\n" + L.t("format_hint")
            + "\n\n" + L.t("phone_link_hint")
            + "\n\n" + L.t("web_search_prompt")
            + whatArrivesAlongside()
    }

    static func code(language: CodeLanguage) -> String {
        greeting() + "\n\n" + L.t("code_prompt")
            + "\n\n" + L.fmt("code_fence_line", "```" + language.fenceTag)
            + whatArrivesAlongside()
    }

    private static func greeting() -> String {
        var sysText = L.t("system_lang")
        sysText += "\n\nCurrent date: \(currentDate()). "
        sysText += "Local time: \(currentTime()) (\(TimeZone.current.identifier)). "
        sysText += "Treat any event dated after today as unknown to you."
        return sysText
    }

    private static func whatArrivesAlongside() -> String {
        "\n\n" + L.t("memory_prompt")
            + "\n\n" + L.t("picture_honesty_prompt")
            + "\n\n" + Self.fileProtocol
    }

    static let fileProtocol = PromptLibrary.text("chat_file_protocol")

    static func currentDate() -> String {
        Formatters.systemDate(Date())
    }

    static func currentTime() -> String {
        Formatters.systemTime(Date())
    }

    static func currentMoment() -> String {
        currentDate() + " " + currentTime() + " (" + TimeZone.current.identifier + ")"
    }
}
