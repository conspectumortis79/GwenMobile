import GwenMobileKit
import Foundation

extension ToolRouter {
    static func decisions(from data: Data) -> [ToolDecision] {
        toolCalls(from: data).compactMap { map(name: $0.name, arguments: $0.arguments) }
    }

    static func toolCalls(from data: Data) -> [ToolCall] {
        guard let found = firstChoice(from: data),
              let raw = found.message["tool_calls"] as? [[String: Any]] else { return [] }
        return calls(from: raw)
    }

    static func arguments(from data: Data, named name: String) -> [String: Any]? {
        guard let call = toolCalls(from: data).first(where: { $0.name == name }),
              let raw = call.arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            return nil
        }
        return object
    }

    static func firstChoice(from data: Data) -> (choice: [String: Any], message: [String: Any])? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let choice = choices.first,
              let message = choice["message"] as? [String: Any] else { return nil }
        return (choice, message)
    }

    static func calls(from raw: [[String: Any]]) -> [ToolCall] {
        raw.compactMap { entry -> ToolCall? in
            guard let function = entry["function"] as? [String: Any] else { return nil }
            let name = function["name"] as? String ?? ""
            let arguments = function["arguments"] as? String ?? ""
            guard !name.isEmpty else { return nil }
            return ToolCall(name: name, arguments: arguments)
        }
    }

    static func deduped(_ terms: [String]) -> [String] {
        var kept: [String] = []
        for term in terms where !term.isEmpty && !kept.contains(term) { kept.append(term) }
        return kept
    }

    static func mode(_ args: [String: Any]) -> TravelMode {
        TravelMode(rawValue: args["mode"] as? String ?? "") ?? .automatic
    }

    private typealias Mapper = @Sendable ([String: Any], Data?) -> ToolDecision?

    private static let mappers: [String: Mapper] = [
        answerTool: { args, _ in
            let keys = (args["memory"] as? [String] ?? []).map(EntityKey.normalized)
                .filter { !$0.isEmpty }
            return ToolDecision(route: .chat, memoryKeys: keys)
        },
        memoryTool: { args, _ in
            MemoryRequest.from(args).map { ToolDecision(route: .memory($0)) } ?? ToolDecision(route: .chat)
        },
        historyTool: { _, _ in ToolDecision(route: .history) },
        weatherTool: { args, _ in ToolDecision(route: .weather(WeatherRequest.from(args))) },
        appStatusTool: { _, _ in ToolDecision(route: .appStatus) },
        scanTool: { args, _ in ToolDecision(route: .scanDocument(ScanRequest.from(args))) },
        searchTool: { args, _ in
            ToolDecision(route: .chat, searchQuery: ToolDecision.text(args, "query"),
                         detailWish: args["detail"] as? Bool ?? false)
        },
        findTool: { args, _ in
            let query = ToolDecision.text(args, "query")
            return ToolDecision(route: query.map(SendRoute.pictureSearch) ?? .chat, pictureQuery: query)
        },
        codeTool: { args, _ in
            ToolDecision(route: .code(language: CodeLanguage(toolValue: ToolDecision.text(args, "language"))))
        },
        editTool: { args, _ in
            ToolDecision(route: .imageEdit, pictureInstruction: ToolDecision.text(args, "instruction"),
                         pictureMonochrome: args["monochrome"] as? Bool ?? false)
        },
        monochromeTool: { _, _ in
            ToolDecision(route: .imageEdit, pictureMonochrome: true)
        },
        translateTool: { args, _ in
            ToolDecision(route: .translate(ToolRouter.translation(from: args)))
        },
        createTool: { args, _ in
            ToolDecision(route: .imageCreate, picturePrompt: ToolDecision.text(args, "prompt"))
        },
        videoTool: { args, _ in
            VideoRequest.from(args).map { ToolDecision(route: .videoCreate($0)) }
                ?? ToolDecision(route: .chat)
        },
        placeTool: { args, _ in
            let query = ToolDecision.text(args, "query") ?? ""
            let terms = ToolRouter.deduped([query] + (args["terms"] as? [String] ?? []))
            return ToolDecision(route: .nearbyPlace(terms: terms, mode: ToolRouter.mode(args)),
                                searchQuery: query)
        },
        priceTool: { args, _ in
            let terms = ToolRouter.deduped(args["terms"] as? [String] ?? [])
            guard !terms.isEmpty else { return ToolDecision(route: .chat) }
            return ToolDecision(route: .priceSearch(terms: terms,
                                                    country: ToolDecision.text(args, "country"),
                                                    nearby: args["nearby"] as? Bool ?? false))
        },
        watchPriceTool: { args, _ in
            PriceWatchRequest.from(args).map { ToolDecision(route: .priceWatch($0)) }
                ?? ToolDecision(route: .chat)
        },
        briefingTool: { args, _ in
            ToolDecision(route: .dayBriefing(DayBriefingRequest.from(args)))
        },
        routeTool: { args, _ in
            let destination = ToolDecision.text(args, "destination") ?? ""
            let terms = ToolRouter.deduped([destination] + (args["terms"] as? [String] ?? []))
            return ToolDecision(route: .routeToPlace(terms: terms, mode: ToolRouter.mode(args)),
                                searchQuery: destination)
        },
        callTool: { args, _ in
            ContactRequest.from(args).map { ToolDecision(route: .call($0)) } ?? ToolDecision(route: .chat)
        },
        clockTool: { args, _ in
            ClockRequest.from(args).map { ToolDecision(route: .clock($0)) } ?? ToolDecision(route: .chat)
        },
        musicTool: { args, _ in
            MusicRequest.from(args).map { ToolDecision(route: .music($0)) } ?? ToolDecision(route: .chat)
        },
        messageTool: { args, _ in
            MessageRequest.from(args).map { ToolDecision(route: .message($0)) } ?? ToolDecision(route: .chat)
        },
        calendarTool: { _, data in
            guard let data, let plan = try? JSONDecoder().decode(QwenAPI.CalendarPlan.self, from: data),
                  plan.action != .none else { return ToolDecision(route: .chat) }
            return ToolDecision(route: .calendar, calendarPlan: plan)
        },
        reminderTool: { _, data in
            guard let data, let plan = try? JSONDecoder().decode(ReminderPlan.self, from: data),
                  plan.action != .none, let request = ReminderRequest(plan: plan) else {
                return ToolDecision(route: .chat)
            }
            return ToolDecision(route: .reminder(request))
        },
        timerTool: { args, _ in
            TimerRequest.from(args).map { ToolDecision(route: .timer($0)) } ?? ToolDecision(route: .chat)
        },
        readAloudTool: { args, _ in
            ReadAloudRequest.from(args).map { ToolDecision(route: .readAloud($0)) } ?? ToolDecision(route: .chat)
        },
        readAnswerTool: { _, _ in ToolDecision(route: .readAnswer) },
    ]

    static func map(name: String, arguments: String) -> ToolDecision? {
        let data = arguments.data(using: .utf8)
        let args = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        return mappers[name]?(args, data)
    }

    static func carriesOnlyPictures(text: String, pictures: Int) -> Bool {

        text.trimmed.isEmpty && pictures > 0
    }

    static func translation(from args: [String: Any]) -> TranslationJob {
        TranslationJob(text: ToolDecision.text(args, "text") ?? "",
                       targetCode: ToolDecision.text(args, "target") ?? TranslationLanguages.fallbackTarget,
                       sourceCode: ToolDecision.text(args, "source"))
    }
}

extension DayBriefingRequest {
    static func from(_ args: [String: Any]) -> DayBriefingRequest {
        let day = BriefingDay(rawValue: args["day"] as? String ?? "")
        return DayBriefingRequest(day: day ?? .today)
    }
}

extension PriceWatchRequest {
    static func from(_ args: [String: Any]) -> PriceWatchRequest? {
        guard let raw = args["action"] as? String, let action = PriceWatchAction(rawValue: raw) else {
            return nil
        }
        let terms = ToolRouter.deduped(PriceWatch.cleanTerms(args["terms"] as? [String] ?? []))
        let goal = LooseNumber.value(args["goal"])
        let interval = (args["intervalHours"] as? Int).map(PriceWatch.clampInterval)
        let country = ToolDecision.text(args, "country")
        let key = ToolDecision.text(args, "key").map(EntityKey.normalized)
        switch action {
        case .create:
            guard !terms.isEmpty, let goal, goal > 0, goal <= PriceWatch.maximumGoal else { return nil }
            return PriceWatchRequest(action: .create, terms: terms, goal: goal, country: country,
                                     intervalHours: interval)
        case .update:
            guard !terms.isEmpty || key?.isEmpty == false, goal != nil || interval != nil else {
                return nil
            }
            return PriceWatchRequest(action: .update, terms: terms, goal: goal, country: country,
                                     intervalHours: interval, key: key)
        case .delete, .check:
            guard !terms.isEmpty || key?.isEmpty == false else { return nil }
            return PriceWatchRequest(action: action, terms: terms, country: country, key: key)
        case .list:
            return PriceWatchRequest(action: .list)
        }
    }
}

extension MemoryRequest {
    static func from(_ args: [String: Any]) -> MemoryRequest? {
        guard let raw = args["action"] as? String, let action = Action(rawValue: raw) else { return nil }
        let text = ToolDecision.text(args, "text")
        let category = ToolDecision.text(args, "category").flatMap(MemoryCategory.init(rawValue:))
        let date = ToolDecision.text(args, "date").flatMap(day(from:))
        let interval = args["intervalMonths"] as? Int
        let key = ToolDecision.text(args, "key").map(EntityKey.normalized)
        let replace = ToolDecision.text(args, "replace").map(EntityKey.normalized)
        switch action {
        case .create, .suggest:
            guard let text, !text.isEmpty else { return nil }
            return MemoryRequest(action: action, text: text, category: category ?? .fallback,
                                 date: date, intervalMonths: interval, replaceKey: replace)
        case .forget:
            guard let key, !key.isEmpty else { return nil }
            return MemoryRequest(action: .forget, key: key)
        case .list:
            return MemoryRequest(action: .list)
        }
    }

    private static func day(from raw: String) -> Date? {
        Formatters.eventDay(from: raw) ?? Formatters.isoDate(from: raw)
    }
}
