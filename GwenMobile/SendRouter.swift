import Foundation

enum ImageRoute: String, Sendable {
    case edit
    case create
    case chat
}

struct SendContext: Equatable {
    var attachedImage = false
    var rememberedImage = false
    var intent: ImageRoute? = nil

    func withoutIntent() -> SendContext {
        var copy = self
        copy.intent = nil
        return copy
    }
}

enum SendRoute: Equatable {
    case imageEdit
    case imageCreate
    case calendar
    case chart(webData: Bool)
    case chat
}

enum SendRouter {
    static func route(text: String, context: SendContext) -> SendRoute {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return .chat }
        if ChartIntent.looksLikeChartRequest(body) { return .chart(webData: ChartIntent.wantsWebData(body)) }
        if context.attachedImage { return attachedRoute(body, intent: context.intent) }
        return conversationRoute(body, context: context)
    }

    static func needsIntentDetection(text: String, context: SendContext) -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, context.attachedImage || context.rememberedImage else { return false }
        let decided = route(text: body, context: context.withoutIntent())
        if context.attachedImage { return decided == .chat || decided == .imageCreate }
        return decided == .chat
    }

    private static func attachedRoute(_ body: String, intent: ImageRoute?) -> SendRoute {
        if let intent { return route(for: intent) }
        if IntentHeuristics.looksLikeImageRequest(body), !IntentHeuristics.looksLikeEditRequest(body) {
            return .imageCreate
        }
        return .chat
    }

    private static func conversationRoute(_ body: String, context: SendContext) -> SendRoute {
        if IntentHeuristics.looksLikeImageRequest(body), !IntentHeuristics.looksLikeEditRequest(body) {
            return .imageCreate
        }
        if IntentHeuristics.looksLikeCalendarRequest(body) { return .calendar }
        if context.rememberedImage, context.intent == .create, IntentHeuristics.looksLikeEditRequest(body) {
            return .imageEdit
        }
        if let intent = context.intent, intent != .chat { return route(for: intent) }
        if context.rememberedImage, context.intent == nil, IntentHeuristics.looksLikeEditRequest(body) {
            return .imageEdit
        }
        return .chat
    }

    private static func route(for intent: ImageRoute) -> SendRoute {
        switch intent {
        case .edit: return .imageEdit
        case .create: return .imageCreate
        case .chat: return .chat
        }
    }
}
