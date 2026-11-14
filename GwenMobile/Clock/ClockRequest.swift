import GwenMobileKit
import Foundation

struct ClockRequest: Equatable, Sendable {
    var timeZone: String?
    var place: String?

    var zone: TimeZone? { timeZone.flatMap(TimeZone.init(identifier:)) }

    var stepWords: String { StepWords.joined(timeZone, place) }

    var placeName: String? {
        if let place, !place.isEmpty { return place }
        guard let timeZone, timeZone.contains("/") else { return nil }
        return timeZone.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
    }

    static func from(_ args: [String: Any]) -> ClockRequest? {
        let request = ClockRequest(timeZone: ToolDecision.text(args, "timeZone"),
                                   place: ToolDecision.text(args, "place"))
        if request.timeZone != nil { return request.zone == nil ? nil : request }
        return request.place == nil ? request : nil
    }
}
