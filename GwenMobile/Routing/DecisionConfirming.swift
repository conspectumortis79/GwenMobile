import GwenMobileKit
import Foundation

protocol DecisionConfirming: Sendable {
    func checked(_ decision: ToolDecision, wish: String,
                 asking ask: (String) async -> ToolDecision?) async -> ToolDecision
}

struct WeatherDayCheck: DecisionConfirming {
    static let hint = PromptLibrary.text("check_weather_day",
                                         ["relative_days": PromptLibrary.text("router_relative_days")])

    var now: @Sendable () -> Date = { Date() }
    var calendar = Calendar.current

    func checked(_ decision: ToolDecision, wish: String,
                 asking ask: (String) async -> ToolDecision?) async -> ToolDecision {
        guard case .weather(let request) = decision.route, let hint = hint(for: request),
              let fresh = await ask(hint), case .weather(let renewed) = fresh.route,
              renewed.namesADay else { return decision }
        return fresh
    }

    func hint(for request: WeatherRequest) -> String? {
        guard request.namesADay else { return Self.hint }
        guard let date = request.date, let offset = request.offset,
              let ahead = request.daysAhead(from: now(), calendar: calendar), ahead != offset else { return nil }
        flowMarkPersonal("WETTER tage_widerspruch datum=\(date) gerechnet=+\(ahead)d zaehler=+\(offset)d")
        return PromptLibrary.text("check_weather_day_conflict",
                                  ["date": date, "date_days": String(ahead), "day_offset": String(offset),
                                   "relative_days": PromptLibrary.text("router_relative_days")])
    }
}

struct PictureIntentCheck: DecisionConfirming {
    static let hint = PromptLibrary.text("check_picture_intent")

    func checked(_ decision: ToolDecision, wish: String,
                 asking ask: (String) async -> ToolDecision?) async -> ToolDecision {
        guard case .pictureSearch = decision.route else { return decision }
        guard let fresh = await ask(Self.hint), case .imageCreate = fresh.route else { return decision }
        return fresh
    }
}

struct NearbyWishCheck: DecisionConfirming {
    func checked(_ decision: ToolDecision, wish: String,
                 asking ask: (String) async -> ToolDecision?) async -> ToolDecision {
        await PlaceWishConfirmation.checkedNearby(decision, wish: wish, asking: ask)
    }
}

struct ReminderActionCheck: DecisionConfirming {
    static let hint = PromptLibrary.text("check_reminder_action")

    func checked(_ decision: ToolDecision, wish: String,
                 asking ask: (String) async -> ToolDecision?) async -> ToolDecision {
        let words = wish.split(whereSeparator: \.isWhitespace)
        guard case .reminder(let request) = decision.route, request.action == .create,
              request.due == nil, request.minutes == nil, request.seconds == nil,
              words.count > 1, let last = words.last, last.count <= 3 else { return decision }
        guard let fresh = await ask(Self.hint), case .reminder(let renewed) = fresh.route,
              renewed.action == .complete else { return decision }
        var kept = fresh
        kept.wish = decision.wish
        kept.standalone = decision.standalone
        return kept
    }
}

struct PriceIntentCheck: DecisionConfirming {
    static let hint = PromptLibrary.text("check_price_intent")

    func checked(_ decision: ToolDecision, wish: String,
                 asking ask: (String) async -> ToolDecision?) async -> ToolDecision {
        guard decision.stepKind == .chat, decision.searchQuery == nil else { return decision }
        guard let fresh = await ask(Self.hint), case .priceSearch = fresh.route else { return decision }
        var kept = fresh
        kept.wish = decision.wish
        kept.standalone = decision.standalone
        return kept
    }
}

enum PictureWishMerge {
    static func request(baseURL: String, key: String, model: String,
                        first: String, second: String,
                        thinking: ThinkingDirective) throws -> URLRequest {
        try ChatRequest.post(baseURL: baseURL, key: key, model: model,
                             messages: [ChatPayload.system(PromptLibrary.text("check_picture_duplicate")),
                                        ChatPayload.user("1. \(first)\n2. \(second)")],
                             stream: false, thinking: thinking, timeout: APITimeout.chatRequest,
                             temperature: 0,
                             extra: ["max_tokens": 8])
    }

    static func same(_ answer: String?) -> Bool {
        let folded = TextFolding.fold(answer ?? "")
        let words = folded.split { !$0.isLetter }
        guard words.contains(where: { $0 == "same" }),
              !words.contains(where: { $0 == "different" }),
              !words.contains(where: { $0 == "not" || $0 == "no" || $0 == "never" }),
              !folded.contains("n't"), !folded.contains("n’t") else { return false }
        return true
    }

    static func merged(_ decisions: [ToolDecision],
                       same: (ToolDecision, ToolDecision) async -> Bool) async -> [ToolDecision] {
        var kept: [ToolDecision] = []
        for decision in decisions {
            guard decision.stepKind == .create else {
                kept.append(decision)
                continue
            }
            var replacement: Int?
            for index in kept.indices where kept[index].stepKind == .create {
                guard await same(kept[index], decision) else { continue }
                replacement = index
                break
            }
            if let index = replacement {
                if decision.picturePromptText.count > kept[index].picturePromptText.count {
                    kept[index] = decision
                }
            } else {
                kept.append(decision)
            }
        }
        return kept
    }
}
