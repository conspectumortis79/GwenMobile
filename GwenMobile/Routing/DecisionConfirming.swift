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
