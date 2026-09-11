import Foundation

enum ImageRoute: String, Sendable {
    case edit
    case create
    case chat
}

enum SendRoute: Equatable {
    case imageEdit
    case imageCreate
    case calendar
    case chart(webData: Bool)
    case chat
}

enum SendRouter {
    static func route(text: String, hasImage: Bool, intent: ImageRoute?) -> SendRoute {
        guard hasImage else {
            if ChartIntent.looksLikeChartRequest(text) { return .chart(webData: ChartIntent.wantsWebData(text)) }
            if IntentHeuristics.looksLikeImageRequest(text) { return .imageCreate }
            if IntentHeuristics.looksLikeCalendarRequest(text) { return .calendar }
            return .chat
        }
        guard !text.isEmpty else { return .chat }
        if let intent {
            switch intent {
            case .edit: return .imageEdit
            case .create: return .imageCreate
            case .chat: return .chat
            }
        }
        if IntentHeuristics.looksLikeImageRequest(text), !IntentHeuristics.looksLikeEditRequest(text) {
            return .imageCreate
        }
        return .chat
    }
}
