import Foundation

enum SearchMarker {
    static let token = "[[SEARCH]]"
}

enum ImageRoute: String, Sendable {
    case edit
    case create
    case chat
}

enum SendRoute: Equatable {
    case imageEdit
    case imageCreate
    case calendar
    case chat
}

enum SendRouter {
    static func route(text: String, hasImage: Bool, intent: ImageRoute?) -> SendRoute {
        guard hasImage else {
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
