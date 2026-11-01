import GwenMobileKit
import Foundation

extension ToolRouter {
    private struct ToolSet: @unchecked Sendable {
        let tools: [[String: Any]]
    }

    private static let toolCache = LockedValue([String: ToolSet]())

    private static func modeSchema() -> [String: Any] {
        [
            "type": "string",
            "enum": TravelMode.allCases.map { $0.rawValue },
            "description": argument("travel_mode", "mode"),
        ]
    }

    static func tools(attachable: Bool, translatesOnDevice: Bool = true,
                      compact: Bool = false) -> [[String: Any]] {
        let key = "\(attachable)-\(translatesOnDevice)-\(compact)"
        return toolCache.mutate { stored in
            if let found = stored[key] { return found.tools }
            let made = buildTools(attachable: attachable, translatesOnDevice: translatesOnDevice)
            let result = compact ? made.map { compactSchema($0) } : made
            stored[key] = ToolSet(tools: result)
            return result
        }
    }

    private static func compactSchema(_ value: Any) -> [String: Any] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        return compactDictionary(dictionary)
    }

    private static func compactDictionary(_ dictionary: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            if key == "description", let text = value as? String {
                result[key] = String(text.prefix(80))
            } else if let nested = value as? [String: Any] {
                result[key] = compactDictionary(nested)
            } else if let list = value as? [Any] {
                result[key] = list.map { item -> Any in
                    if let nested = item as? [String: Any] { return compactDictionary(nested) }
                    return item
                }
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func buildTools(attachable: Bool, translatesOnDevice: Bool) -> [[String: Any]] {
        var list = chatFunctions()
        list += priceFunctions()
        list.append(briefingFunction())
        list += pictureSearchFunctions()
        list += placeFunctions()
        list += deviceFunctions(translatesOnDevice: translatesOnDevice)
        list.append(memoryFunction())
        list.append(historyFunction())
        list.append(weatherFunction())
        list.append(statusFunction())
        list.append(scanFunction())
        list.append(calendarFunction())
        list.append(reminderFunction())
        if attachable { list.append(editPictureFunction()) }
        if attachable { list.append(monochromeFunction()) }
        list.append(createPictureFunction())
        list.append(createVideoFunction())
        return list
    }

    private static func chatFunctions() -> [[String: Any]] {
        [answerFunction(), searchFunction()]
    }

    private static func priceFunctions() -> [[String: Any]] {
        [priceFunction(), watchPriceFunction()]
    }

    private static func pictureSearchFunctions() -> [[String: Any]] {
        [findPicturesFunction(), codeFunction()]
    }

    private static func placeFunctions() -> [[String: Any]] {
        [placeFunction(), routeFunction()]
    }

    private static func deviceFunctions(translatesOnDevice: Bool) -> [[String: Any]] {
        var list = [callFunction(), clockFunction(), timerFunction(), readAloudFunction(),
                    readAnswerFunction(), musicFunction(), messageFunction()]
        if translatesOnDevice { list.append(translateFunction()) }
        return list
    }

    private static func answerFunction() -> [String: Any] {
        function(answerTool, PromptLibrary.text("tool_answer_in_chat", promptValues),
                 ["memory": ["type": "array", "items": ["type": "string"],
                             "description": argument(answerTool, "memory")]], [])
    }

    private static func searchFunction() -> [String: Any] {
        function(searchTool, PromptLibrary.text("tool_search_web", promptValues),
                 ["query": string(argument(searchTool, "query")),
                  "detail": ["type": "boolean",
                             "description": argument(searchTool, "detail")]],
                 ["query"])
    }

    private static func priceFunction() -> [String: Any] {
        function(priceTool, PromptLibrary.text("tool_compare_prices", promptValues),
                 ["terms": termsSchema(argument(priceTool, "terms")),
                 "country": string(argument(priceTool, "country")),
                 "nearby": ["type": "boolean",
                            "description": argument(priceTool, "nearby")]],
                 ["terms"])
    }

    private static func watchPriceFunction() -> [String: Any] {
        function(watchPriceTool, PromptLibrary.text("tool_watch_price", promptValues),
                 ["action": ["type": "string", "enum": ["create", "update", "delete", "check", "list"],
                             "description": argument(watchPriceTool, "action")],
                  "terms": termsSchema(argument(watchPriceTool, "terms")),
                  "goal": ["type": "number",
                           "description": argument(watchPriceTool, "goal")],
                  "country": string(argument(watchPriceTool, "country")),
                  "intervalHours": ["type": "integer",
                                    "description": argument(watchPriceTool, "intervalHours")],
                  "key": string(argument(watchPriceTool, "key"))],
                 ["action"])
    }

    private static func briefingFunction() -> [String: Any] {
        function(briefingTool, PromptLibrary.text("tool_day_briefing", promptValues),
                 ["day": ["type": "string", "enum": ["today", "tomorrow", "dayAfter"],
                          "description": argument(briefingTool, "day")]],
                 [])
    }

    private static func findPicturesFunction() -> [String: Any] {
        function(findTool, PromptLibrary.text("tool_find_pictures", promptValues),
                 ["query": string(argument(findTool, "query"))], ["query"])
    }

    private static func codeFunction() -> [String: Any] {
        function(codeTool, PromptLibrary.text("tool_write_code", promptValues),
                 ["language": ["type": "string", "enum": CodeLanguage.toolValues,
                               "description": argument(codeTool, "language")]],
                 ["language"])
    }

    private static func placeLikeFunction(_ tool: String, _ promptKey: String, _ field: String) -> [String: Any] {
        function(tool, PromptLibrary.text(promptKey, promptValues),
                 [field: string(argument(tool, field)),
                  "terms": termsSchema(argument(tool, "terms")),
                  "mode": modeSchema()],
                 [field, "terms"])
    }

    private static func placeFunction() -> [String: Any] {
        placeLikeFunction(placeTool, "tool_find_nearby_place", "query")
    }

    private static func routeFunction() -> [String: Any] {
        placeLikeFunction(routeTool, "tool_route_to_place", "destination")
    }

    private static func translateFunction() -> [String: Any] {
        function(translateTool, PromptLibrary.text("tool_translate_text", promptValues),
                 ["text": string(argument(translateTool, "text")),
                 "target": ["type": "string", "enum": TranslationLanguages.codes,
                            "description": argument(translateTool, "target")],
                 "source": ["type": "string", "enum": TranslationLanguages.codes,
                            "description": argument(translateTool, "source")]],
                 ["target"])
    }

    private static func calendarFunction() -> [String: Any] {
        function(calendarTool, PromptLibrary.text("tool_plan_calendar", promptValues),
                 [
                     "action": ["type": "string", "enum": ["create", "update", "delete", "none"]],
                     "title": string(argument(calendarTool, "title")),
                     "start": string(argument(calendarTool, "start")),
                     "end": string(argument(calendarTool, "end")),
                     "location": string(argument(calendarTool, "location")),
                     "notes": string(argument(calendarTool, "notes")),
                     "find": string(argument(calendarTool, "find")),
                     "alerts": ["type": "array", "items": ["type": "integer"],
                                "description": argument(calendarTool, "alerts")],
                     "calendar": string(argument(calendarTool, "calendar")),
                 ], ["action"])
    }

    static func reminderFunction() -> [String: Any] {
        function(reminderTool, PromptLibrary.text("tool_plan_reminder", promptValues),
                 [
                     "action": ["type": "string",
                                "enum": ["create", "update", "complete", "delete", "list"],
                                "description": argument(reminderTool, "action")],
                     "title": string(argument(reminderTool, "title")),
                     "due": string(argument(reminderTool, "due")),
                     "minutes": ["type": "integer",
                                 "description": argument(reminderTool, "minutes")],
                     "seconds": ["type": "integer",
                                 "description": argument(reminderTool, "seconds")],
                     "allDay": ["type": "boolean",
                                "description": argument(reminderTool, "allDay")],
                     "list": string(argument(reminderTool, "list")),
                     "repeat": ["type": "string", "enum": ["daily", "weekly", "monthly", "yearly"],
                                "description": argument(reminderTool, "repeat")],
                     "repeatInterval": ["type": "integer",
                                        "description": argument(reminderTool, "repeatInterval")],
                     "priority": ["type": "string", "enum": ["high", "low"],
                                  "description": argument(reminderTool, "priority")],
                     "location": string(argument(reminderTool, "location")),
                     "proximity": ["type": "string", "enum": ["arrive", "leave"],
                                   "description": argument(reminderTool, "proximity")],
                     "notes": string(argument(reminderTool, "notes")),
                     "find": string(argument(reminderTool, "find")),
                 ], ["action"])
    }

    private static func editPictureFunction() -> [String: Any] {
        function(editTool, PromptLibrary.text("tool_edit_picture", promptValues),
                 ["instruction": string(argument(editTool, "instruction")),
                  "monochrome": ["type": "boolean",
                                 "description": argument(editTool, "monochrome")]],
                 ["instruction", "monochrome"])
    }

    private static func monochromeFunction() -> [String: Any] {
        function(monochromeTool, PromptLibrary.text("tool_make_monochrome", promptValues), [:], [])
    }

    private static func createPictureFunction() -> [String: Any] {
        function(createTool, PromptLibrary.text("tool_create_picture", promptValues),
                 ["prompt": string(argument(createTool, "prompt"))],
                 ["prompt"])
    }

    private static func createVideoFunction() -> [String: Any] {
        function(videoTool, PromptLibrary.text("tool_create_video", promptValues),
                 ["prompt": string(argument(videoTool, "prompt")),
                  "duration": ["type": "integer",
                               "description": argument(videoTool, "duration")],
                  "ratio": ["type": "string", "enum": VideoRatio.allCases.map(\.rawValue),
                            "description": argument(videoTool, "ratio")]],
                 ["prompt"])
    }

    private static func memoryFunction() -> [String: Any] {
        function(memoryTool, PromptLibrary.text("tool_remember_fact", promptValues),
                 ["action": ["type": "string", "enum": ["create", "suggest", "forget", "list"],
                             "description": argument(memoryTool, "action")],
                  "text": string(argument(memoryTool, "text")),
                  "category": ["type": "string",
                               "enum": MemoryCategory.allCases.map(\.rawValue),
                               "description": argument(memoryTool, "category")],
                  "date": string(argument(memoryTool, "date")),
                  "intervalMonths": ["type": "integer",
                                     "description": argument(memoryTool, "intervalMonths")],
                  "key": string(argument(memoryTool, "key")),
                  "replace": string(argument(memoryTool, "replace"))],
                 ["action"])
    }

    private static func historyFunction() -> [String: Any] {
        function(historyTool, PromptLibrary.text("tool_delete_history", promptValues),
                 [:],
                 [])
    }

    private static func statusFunction() -> [String: Any] {
        function(appStatusTool, PromptLibrary.text("tool_check_app_status", promptValues), [:], [])
    }

    private static func weatherFunction() -> [String: Any] {
        function(weatherTool, PromptLibrary.text("tool_tell_weather", promptValues),
                 ["place": string(argument(weatherTool, "place")),
                 "day": ["type": "string", "enum": ["today", "tomorrow", "dayAfter"],
                         "description": argument(weatherTool, "day")],
                 "dayOffset": ["type": "integer",
                               "description": argument(weatherTool, "dayOffset")],
                 "date": string(argument(weatherTool, "date"))],
                 [])
    }

    private static func scanFunction() -> [String: Any] {
        function(scanTool, PromptLibrary.text("tool_scan_document", promptValues),
                 ["kind": ["type": "string", "enum": ScanKind.toolValues,
                           "description": argument(scanTool, "kind")],
                  "remind": ["type": "boolean",
                             "description": argument(scanTool, "remind")]],
                 [])
    }

    private static func callFunction() -> [String: Any] {
        function(callTool, PromptLibrary.text("tool_call_contact", promptValues),
                 ["person": string(argument(callTool, "person")),
                 "group": string(argument(callTool, "group")),
                 "relation": ["type": "string", "enum": ContactRelation.toolValues,
                              "description": argument(callTool, "relation",
                                                     ["relation_none": ContactRelation.noneValue])],
                 "number": ["type": "string", "enum": PhoneKind.toolValues,
                            "description": argument(callTool, "number",
                                                   ["phone_any": PhoneKind.anyValue])]],
                 ["person"])
    }

    private static func clockFunction() -> [String: Any] {
        function(clockTool, PromptLibrary.text("tool_tell_time", promptValues),
                 ["timeZone": string(argument(clockTool, "timeZone")),
                 "place": string(argument(clockTool, "place"))],
                 [])
    }

    private static func messageFunction() -> [String: Any] {
        function(messageTool, PromptLibrary.text("tool_send_message", promptValues),
                 ["person": string(argument(messageTool, "person")),
                 "group": string(argument(messageTool, "group")),
                 "relation": ["type": "string", "enum": ContactRelation.toolValues,
                              "description": argument(messageTool, "relation",
                                                      ["relation_none": ContactRelation.noneValue])],
                 "text": string(argument(messageTool, "text"))],
                 ["person", "text"])
    }

    private static func timerFunction() -> [String: Any] {
        function(timerTool, PromptLibrary.text("tool_set_timer", promptValues),
                 ["minutes": ["type": "integer",
                              "description": argument(timerTool, "minutes")],
                  "seconds": ["type": "integer",
                              "description": argument(timerTool, "seconds")],
                  "title": string(argument(timerTool, "title"))],
                 [])
    }

    private static func readAloudFunction() -> [String: Any] {
        function(readAloudTool, PromptLibrary.text("tool_set_read_aloud", promptValues),
                 ["enabled": ["type": "boolean",
                              "description": argument(readAloudTool, "enabled")]],
                 ["enabled"])
    }

    private static func readAnswerFunction() -> [String: Any] {
        function(readAnswerTool, PromptLibrary.text("tool_read_answer", promptValues),
                 [:], [])
    }

    private static func musicFunction() -> [String: Any] {
        function(musicTool, PromptLibrary.text("tool_control_music", promptValues),
                 ["action": ["type": "string", "enum": MusicAction.allCases.map(\.rawValue),
                             "description": argument(musicTool, "action")],
                  "query": string(argument(musicTool, "query")),
                  "artist": string(argument(musicTool, "artist")),
                  "kind": ["type": "string", "enum": MusicKind.allCases.map(\.rawValue),
                           "description": argument(musicTool, "kind")],
                  "service": ["type": "string", "enum": MusicService.toolValues,
                              "description": argument(musicTool, "service",
                                                      ["service_any": MusicService.anyValue])]],
                 ["action"])
    }

    private static func function(_ name: String, _ description: String, _ properties: [String: Any],
                                 _ required: [String]) -> [String: Any] {
        ["type": "function",
         "function": ["name": name, "description": description,
                      "parameters": ["type": "object", "properties": properties, "required": required]]]
    }

    private static func argument(_ tool: String, _ name: String,
                                 _ values: [String: String] = [:]) -> String {
        PromptLibrary.field("args_" + tool, name, values)
    }

    private static func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func termsSchema(_ description: String) -> [String: Any] {
        ["type": "array", "items": ["type": "string"], "description": description]
    }

    static func sourceFilterTools() -> [[String: Any]] {
        [function(keepSourcesTool, PromptLibrary.text("tool_keep_sources"),
                  ["sources": ["type": "array", "items": ["type": "integer"],
                               "description": argument(keepSourcesTool, "sources")]],
                  ["sources"])]
    }

    static func productTools() -> [[String: Any]] {
        [function(productTool,
                  PromptLibrary.text("tool_report_product", promptValues),
                  ["product": string(argument(productTool, "product")),
                  "brand": string(argument(productTool, "brand")),
                  "price": string(argument(productTool, "price")),
                  "ean": string(argument(productTool, "ean"))],
                  ["product"])]
    }

    private static func statusTool(_ tool: String, _ promptKey: String, _ field: String) -> [String: Any] {
        function(tool, PromptLibrary.text(promptKey, promptValues),
                 ["status": statusSchema(argument(tool, "status")),
                  field: string(argument(tool, field))],
                 ["status", field])
    }

    static func queryResolverTools() -> [[String: Any]] {
        [statusTool(resolveQueryTool, "tool_resolve_search_query", "query")]
    }

    static func imagePromptTools() -> [[String: Any]] {
        [statusTool(composeImagePromptTool, "tool_compose_image_prompt", "prompt")]
    }

    static func priceReportTools() -> [[String: Any]] {
        let tool = LivePriceWatchChecker.reportTool
        return [function(tool, PromptLibrary.text("tool_report_price"),
                         ["price": ["type": "number", "description": argument(tool, "price")],
                          "currency": string(argument(tool, "currency")),
                          "shop": string(argument(tool, "shop")),
                          "source": ["type": "integer", "description": argument(tool, "source")],
                          "product": string(argument(tool, "product"))],
                         ["price", "source", "product"])]
    }

    static func translationTools() -> [[String: Any]] {
        [function(reportTranslationTool, PromptLibrary.text("tool_report_translation"),
                  ["translation": string(argument(reportTranslationTool, "translation"))],
                  ["translation"])]
    }

    private static func statusSchema(_ description: String) -> [String: Any] {
        ["type": "string", "enum": StructuredToolStatus.allCases.map(\.rawValue),
         "description": description]
    }
}
