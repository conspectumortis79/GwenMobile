import GwenMobileKit
import Foundation

struct ToolCall: Equatable {
    var name: String
    var arguments: String
}

enum StructuredToolStatus: String, CaseIterable, Sendable {
    case resolved
    case unresolved
}

struct ToolDecision: Equatable {
    var route: SendRoute
    var searchQuery: String?
    var detailWish: Bool = false
    var pictureInstruction: String?
    var picturePrompt: String?
    var pictureQuery: String?
    var pictureMonochrome: Bool = false
    var calendarPlan: QwenAPI.CalendarPlan?
    var memoryKeys: [String] = []
    var wish: String?
    var standalone = false

    var calendarAction: QwenAPI.CalendarPlan.Action? { calendarPlan?.action }

    static func text(_ args: [String: Any], _ key: String) -> String? {
        let value = (args[key] as? String)?.trimmed
        return value?.isEmpty == false ? value : nil
    }
}

enum ToolRouter {
    static let answerTool = "answer_in_chat"
    static let searchTool = "search_web"
    static let keepSourcesTool = "keep_sources"
    static let findTool = "find_pictures"
    static let codeTool = "write_code"
    static let editTool = "edit_picture"
    static let monochromeTool = "make_monochrome"
    static let translateTool = "translate_text"
    static let createTool = "create_picture"
    static let videoTool = "create_video"
    static let calendarTool = "plan_calendar"
    static let reminderTool = "plan_reminder"
    static let timerTool = "set_timer"
    static let readAloudTool = "set_read_aloud"
    static let readAnswerTool = "read_answer"
    static let placeTool = "find_nearby_place"
    static let routeTool = "route_to_place"
    static let priceTool = "compare_prices"
    static let watchPriceTool = "watch_price"
    static let briefingTool = "day_briefing"
    static let productTool = "report_product"
    static let callTool = "call_contact"
    static let clockTool = "tell_time"
    static let musicTool = "control_music"
    static let messageTool = "send_message"
    static let memoryTool = "remember_fact"
    static let historyTool = "delete_history"
    static let weatherTool = "tell_weather"
    static let appStatusTool = "check_app_status"
    static let scanTool = "scan_document"
    static let resolveQueryTool = "resolve_search_query"
    static let composeImagePromptTool = "compose_image_prompt"
    static let reportTranslationTool = "report_translation"

    static let promptValues: [String: String] = [
        "answer_tool": answerTool,
        "search_tool": searchTool,
        "find_tool": findTool,
        "code_tool": codeTool,
        "edit_tool": editTool,
        "translate_tool": translateTool,
        "create_tool": createTool,
        "video_tool": videoTool,
        "calendar_tool": calendarTool,
        "reminder_tool": reminderTool,
        "timer_tool": timerTool,
        "read_aloud_tool": readAloudTool,
        "read_answer_tool": readAnswerTool,
        "place_tool": placeTool,
        "route_tool": routeTool,
        "price_tool": priceTool,
        "watch_tool": watchPriceTool,
        "briefing_tool": briefingTool,
        "product_tool": productTool,
        "call_tool": callTool,
        "clock_tool": clockTool,
        "music_tool": musicTool,
        "message_tool": messageTool,
        "memory_tool": memoryTool,
        "history_tool": historyTool,
        "weather_tool": weatherTool,
        "app_status_tool": appStatusTool,
        "scan_tool": scanTool,
        "resolve_query_tool": resolveQueryTool,
        "compose_image_prompt_tool": composeImagePromptTool,
        "report_translation_tool": reportTranslationTool,
    ]

    static let maxTokens = 700
    static let confirmations: [any DecisionConfirming] = [NearbyWishCheck(), MessageLanguageCheck(),
                                                          PictureIntentCheck(), WeatherDayCheck()]
    static let decisionAttempts = 2
    static let automaticChoice = "auto"
    static let forcedChoice = "required"
}
