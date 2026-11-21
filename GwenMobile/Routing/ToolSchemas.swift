import GwenMobileKit
import Foundation

extension ToolRouter {
    private struct ToolSet: @unchecked Sendable {
        let tools: [[String: Any]]
    }

    private static let toolCache = LockedValue([String: ToolSet]())

    private static func modeSchema() -> [String: Any] {
        choice(TravelMode.allCases.map { $0.rawValue }, argument("travel_mode", "mode"))
    }

    static let independenceField = "independent"

    static func tools(attachable: Bool, translatesOnDevice: Bool = true,
                      compact: Bool = false) -> [[String: Any]] {
        let key = "\(attachable)-\(translatesOnDevice)-\(compact)"
        return toolCache.mutate { stored in
            if let found = stored[key] { return found.tools }
            let made = buildTools(attachable: attachable, translatesOnDevice: translatesOnDevice)
                .map(withIndependence)
            let result = compact ? made.map { compactSchema($0) } : made
            stored[key] = ToolSet(tools: result)
            return result
        }
    }

    private static func withIndependence(_ tool: [String: Any]) -> [String: Any] {
        let function = tool["function"] as? [String: Any] ?? [:]
        var parameters = function["parameters"] as? [String: Any] ?? [:]
        var properties = parameters["properties"] as? [String: Any] ?? [:]
        properties[independenceField] = boolean(PromptLibrary.field("args_independent", independenceField))
        parameters["properties"] = properties
        var made = tool
        made["function"] = function.merging(["parameters": parameters]) { _, fresh in fresh }
        return made
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
        promptTool(answerTool, "tool_answer_in_chat",
             ["memory": strings(argument(answerTool, "memory"))], [])
    }

    private static func searchFunction() -> [String: Any] {
        promptTool(searchTool, "tool_search_web",
             ["query": field(searchTool, "query"),
              "detail": boolean(argument(searchTool, "detail"))], ["query"])
    }

    private static func priceFunction() -> [String: Any] {
        promptTool(priceTool, "tool_compare_prices",
             ["terms": strings(argument(priceTool, "terms")),
              "country": field(priceTool, "country"),
              "nearby": boolean(argument(priceTool, "nearby"))], ["terms"])
    }

    private static func watchPriceFunction() -> [String: Any] {
        promptTool(watchPriceTool, "tool_watch_price",
             ["action": choiceField(watchPriceTool, "action", ["create", "update", "delete", "check", "list"]),
              "terms": strings(argument(watchPriceTool, "terms")),
              "goal": number(argument(watchPriceTool, "goal")),
              "country": field(watchPriceTool, "country"),
              "intervalHours": integer(argument(watchPriceTool, "intervalHours")),
              "key": field(watchPriceTool, "key")], ["action"])
    }

    private static func briefingFunction() -> [String: Any] {
        promptTool(briefingTool, "tool_day_briefing",
             ["day": choiceField(briefingTool, "day", ["today", "tomorrow", "dayAfter"])], [])
    }

    private static func findPicturesFunction() -> [String: Any] {
        promptTool(findTool, "tool_find_pictures", ["query": field(findTool, "query")], ["query"])
    }

    private static func codeFunction() -> [String: Any] {
        promptTool(codeTool, "tool_write_code",
             ["language": choiceField(codeTool, "language", CodeLanguage.toolValues)], ["language"])
    }

    private static func placeLikeFunction(_ toolName: String, _ promptKey: String, _ fieldName: String,
                                          withCount: Bool = false) -> [String: Any] {
        var properties: [String: Any] = [fieldName: field(toolName, fieldName),
                                         "terms": strings(argument(toolName, "terms")),
                                         "mode": modeSchema()]
        if withCount {
            properties["count"] = integer(argument(placeTool, "count"),
                                          minimum: 1, maximum: PlaceSearch.maxResults)
        }
        return promptTool(toolName, promptKey, properties, [fieldName, "terms"])
    }

    private static func placeFunction() -> [String: Any] {
        placeLikeFunction(placeTool, "tool_find_nearby_place", "query", withCount: true)
    }

    private static func routeFunction() -> [String: Any] {
        placeLikeFunction(routeTool, "tool_route_to_place", "destination")
    }

    private static func translateFunction() -> [String: Any] {
        promptTool(translateTool, "tool_translate_text",
             ["text": field(translateTool, "text"),
              "target": choiceField(translateTool, "target", TranslationLanguages.codes),
              "source": choiceField(translateTool, "source", TranslationLanguages.codes)],
             ["target"])
    }

    private static func calendarFunction() -> [String: Any] {
        promptTool(calendarTool, "tool_plan_calendar",
             ["action": choice(["create", "update", "delete", "none"]),
              "title": field(calendarTool, "title"),
              "start": field(calendarTool, "start"),
              "end": field(calendarTool, "end"),
              "location": field(calendarTool, "location"),
              "notes": field(calendarTool, "notes"),
              "find": field(calendarTool, "find"),
              "alerts": integers(argument(calendarTool, "alerts")),
              "calendar": field(calendarTool, "calendar")],
             ["action"])
    }

    static func reminderFunction() -> [String: Any] {
        promptTool(reminderTool, "tool_plan_reminder",
             ["action": choiceField(reminderTool, "action",
                                    ["create", "update", "complete", "delete", "list"]),
              "title": field(reminderTool, "title"),
              "due": field(reminderTool, "due"),
              "minutes": integer(argument(reminderTool, "minutes")),
              "seconds": integer(argument(reminderTool, "seconds")),
              "allDay": boolean(argument(reminderTool, "allDay")),
              "list": field(reminderTool, "list"),
              "repeat": choiceField(reminderTool, "repeat", ["daily", "weekly", "monthly", "yearly"]),
              "repeatInterval": integer(argument(reminderTool, "repeatInterval")),
              "priority": choiceField(reminderTool, "priority", ["high", "low"]),
              "location": field(reminderTool, "location"),
              "proximity": choiceField(reminderTool, "proximity", ["arrive", "leave"]),
              "notes": field(reminderTool, "notes"),
              "find": field(reminderTool, "find")],
             ["action"])
    }

    private static func editPictureFunction() -> [String: Any] {
        promptTool(editTool, "tool_edit_picture",
             ["instruction": field(editTool, "instruction"),
              "monochrome": boolean(argument(editTool, "monochrome")),
              "exact": enumStrings(PictureExactEdit.allCases.map(\.rawValue),
                                   argument(editTool, "exact"))],
             ["instruction", "monochrome", "exact"])
    }

    private static func monochromeFunction() -> [String: Any] {
        promptTool(monochromeTool, "tool_make_monochrome", [:], [])
    }

    private static func createPictureFunction() -> [String: Any] {
        promptTool(createTool, "tool_create_picture",
             ["prompt": field(createTool, "prompt")], ["prompt"])
    }

    private static func createVideoFunction() -> [String: Any] {
        promptTool(videoTool, "tool_create_video",
             ["prompt": field(videoTool, "prompt"),
              "duration": integer(argument(videoTool, "duration")),
              "ratio": choiceField(videoTool, "ratio", VideoRatio.allCases.map(\.rawValue))],
             ["prompt"])
    }

    private static func memoryFunction() -> [String: Any] {
        promptTool(memoryTool, "tool_remember_fact",
             ["action": choiceField(memoryTool, "action", ["create", "suggest", "forget", "list"]),
              "text": field(memoryTool, "text"),
              "category": choiceField(memoryTool, "category", MemoryCategory.allCases.map(\.rawValue)),
              "date": field(memoryTool, "date"),
              "intervalMonths": integer(argument(memoryTool, "intervalMonths")),
              "key": field(memoryTool, "key"),
              "replace": field(memoryTool, "replace")],
             ["action"])
    }

    private static func historyFunction() -> [String: Any] {
        promptTool(historyTool, "tool_delete_history", [:], [])
    }

    private static func statusFunction() -> [String: Any] {
        promptTool(appStatusTool, "tool_check_app_status", [:], [])
    }

    private static func weatherFunction() -> [String: Any] {
        promptTool(weatherTool, "tool_tell_weather",
             ["place": field(weatherTool, "place"),
              "day": choiceField(weatherTool, "day", ["today", "tomorrow", "dayAfter"]),
              "dayOffset": integer(argument(weatherTool, "dayOffset")),
              "date": field(weatherTool, "date")],
             [])
    }

    private static func scanFunction() -> [String: Any] {
        promptTool(scanTool, "tool_scan_document",
             ["kind": choiceField(scanTool, "kind", ScanKind.toolValues),
              "remind": boolean(argument(scanTool, "remind"))],
             [])
    }

    private static func callFunction() -> [String: Any] {
        promptTool(callTool, "tool_call_contact",
             ["person": field(callTool, "person"),
              "group": field(callTool, "group"),
              "relation": choiceField(callTool, "relation", ContactRelation.toolValues,
                                      ["relation_none": ContactRelation.noneValue]),
              "number": choiceField(callTool, "number", PhoneKind.toolValues,
                                    ["phone_any": PhoneKind.anyValue])],
             ["person"])
    }

    private static func clockFunction() -> [String: Any] {
        promptTool(clockTool, "tool_tell_time",
             ["timeZone": field(clockTool, "timeZone"),
              "place": field(clockTool, "place")],
             [])
    }

    private static func messageFunction() -> [String: Any] {
        promptTool(messageTool, "tool_send_message",
             ["person": field(messageTool, "person"),
              "group": field(messageTool, "group"),
              "relation": choiceField(messageTool, "relation", ContactRelation.toolValues,
                                      ["relation_none": ContactRelation.noneValue]),
              "text": field(messageTool, "text")],
             ["person", "text"])
    }

    private static func timerFunction() -> [String: Any] {
        promptTool(timerTool, "tool_set_timer",
             ["minutes": integer(argument(timerTool, "minutes")),
              "seconds": integer(argument(timerTool, "seconds")),
              "title": field(timerTool, "title")],
             [])
    }

    private static func readAloudFunction() -> [String: Any] {
        promptTool(readAloudTool, "tool_set_read_aloud",
             ["enabled": boolean(argument(readAloudTool, "enabled"))], ["enabled"])
    }

    private static func readAnswerFunction() -> [String: Any] {
        promptTool(readAnswerTool, "tool_read_answer", [:], [])
    }

    private static func musicFunction() -> [String: Any] {
        promptTool(musicTool, "tool_control_music",
             ["action": choiceField(musicTool, "action", MusicAction.allCases.map(\.rawValue)),
              "query": field(musicTool, "query"),
              "artist": field(musicTool, "artist"),
              "kind": choiceField(musicTool, "kind", MusicKind.allCases.map(\.rawValue)),
              "service": choiceField(musicTool, "service", MusicService.toolValues,
                                     ["service_any": MusicService.anyValue])],
             ["action"])
    }

    static func sourceFilterTools() -> [[String: Any]] {
        [promptTool(keepSourcesTool, "tool_keep_sources",
              ["sources": integers(argument(keepSourcesTool, "sources"))], ["sources"])]
    }

    static func productTools() -> [[String: Any]] {
        [promptTool(productTool, "tool_report_product",
              ["product": field(productTool, "product"),
               "brand": field(productTool, "brand"),
               "price": field(productTool, "price"),
               "ean": field(productTool, "ean")],
              ["product"])]
    }

    private static func statusTool(_ name: String, _ promptKey: String, _ fieldName: String) -> [String: Any] {
        promptTool(name, promptKey,
             ["status": statusSchema(argument(name, "status")),
              fieldName: field(name, fieldName)],
             ["status", fieldName])
    }

    static func queryResolverTools() -> [[String: Any]] {
        [statusTool(resolveQueryTool, "tool_resolve_search_query", "query")]
    }

    static func imagePromptTools() -> [[String: Any]] {
        [statusTool(composeImagePromptTool, "tool_compose_image_prompt", "prompt")]
    }

    static func priceReportTools() -> [[String: Any]] {
        let name = LivePriceWatchChecker.reportTool
        return [promptTool(name, "tool_report_price",
                     ["price": number(argument(name, "price")),
                      "currency": field(name, "currency"),
                      "shop": field(name, "shop"),
                      "source": integer(argument(name, "source")),
                      "product": field(name, "product")],
                     ["price", "source", "product"])]
    }

    static func translationTools() -> [[String: Any]] {
        [promptTool(reportTranslationTool, "tool_report_translation",
              ["translation": field(reportTranslationTool, "translation")], ["translation"])]
    }

    private static func statusSchema(_ description: String) -> [String: Any] {
        choice(StructuredToolStatus.allCases.map(\.rawValue), description)
    }

    private static func promptTool(_ name: String, _ promptKey: String, _ properties: [String: Any],
                                   _ required: [String]) -> [String: Any] {
        function(name, PromptLibrary.text(promptKey, promptValues), properties, required)
    }

    private static func function(_ name: String, _ description: String, _ properties: [String: Any],
                                 _ required: [String]) -> [String: Any] {
        ["type": "function",
         "function": ["name": name, "description": description,
                      "parameters": ["type": "object", "properties": properties, "required": required]]]
    }

    private static func argument(_ name: String, _ key: String,
                                 _ values: [String: String] = [:]) -> String {
        PromptLibrary.field("args_" + name, key, values)
    }

    private static func field(_ toolName: String, _ name: String,
                              _ values: [String: String] = [:]) -> [String: Any] {
        string(argument(toolName, name, values))
    }

    private static func choiceField(_ toolName: String, _ name: String, _ values: [String],
                                    _ labels: [String: String] = [:]) -> [String: Any] {
        choice(values, argument(toolName, name, labels))
    }

    private static func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func boolean(_ description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    private static func number(_ description: String) -> [String: Any] {
        ["type": "number", "description": description]
    }

    private static func integer(_ description: String, minimum: Int? = nil,
                                maximum: Int? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "integer", "description": description]
        if let minimum { schema["minimum"] = minimum }
        if let maximum { schema["maximum"] = maximum }
        return schema
    }

    private static func choice(_ values: [String], _ description: String? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "string", "enum": values]
        if let description { schema["description"] = description }
        return schema
    }

    private static func strings(_ description: String) -> [String: Any] {
        ["type": "array", "items": ["type": "string"], "description": description]
    }

    private static func integers(_ description: String) -> [String: Any] {
        ["type": "array", "items": ["type": "integer"], "description": description]
    }

    private static func enumStrings(_ values: [String], _ description: String) -> [String: Any] {
        ["type": "array", "items": choice(values), "description": description]
    }
}
