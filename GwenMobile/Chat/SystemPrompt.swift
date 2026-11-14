import GwenMobileKit
import Foundation

enum SystemPrompt {
    static func chat() -> String {
        greeting() + "\n\n" + L.t("format_hint")
            + "\n\n" + L.t("phone_link_hint")
            + "\n\n" + L.t("web_search_prompt")
            + whatArrivesAlongside()
            + momentBlock()
    }

    static func code(language: CodeLanguage) -> String {
        greeting() + "\n\n" + L.t("code_prompt")
            + "\n\n" + L.fmt("code_fence_line", "```" + language.fenceTag)
            + whatArrivesAlongside()
            + momentBlock()
    }

    private static func greeting() -> String {
        L.t("system_lang")
    }

    private static func whatArrivesAlongside() -> String {
        "\n\n" + L.t("memory_prompt")
            + "\n\n" + L.t("picture_honesty_prompt")
            + "\n\n" + Self.fileProtocol
    }

    private static func momentBlock() -> String {
        "\n\nCurrent date: \(currentDate()). "
            + "Local time: \(currentTime()) (\(TimeZone.current.identifier)). "
            + "Treat any event dated after today as unknown to you."
    }

    static let fileProtocol = PromptLibrary.text("chat_file_protocol")

    static func currentDate() -> String {
        Formatters.systemDate(Date())
    }

    static func currentTime() -> String {
        Formatters.systemTime(Date())
    }

    static func currentDay() -> String {
        currentDate() + " (" + TimeZone.current.identifier + ")"
    }

    static func currentMoment() -> String {
        currentDate() + " " + currentTime() + " (" + TimeZone.current.identifier + ")"
    }
}
