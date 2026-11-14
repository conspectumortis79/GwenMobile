import GwenMobileKit
import Foundation

struct TimerRequest: Equatable, Sendable {
    var minutes: Int?
    var seconds: Int?
    var title: String?

    var duration: TimeInterval {
        Double(max(0, minutes ?? 0)) * 60 + Double(max(0, seconds ?? 0))
    }

    var stepWords: String {
        StepWords.joined(title, minutes.map { "m\($0)" }, seconds.map { "s\($0)" })
    }

    static func from(_ args: [String: Any]) -> TimerRequest? {
        let request = TimerRequest(minutes: integer(args, "minutes"),
                                   seconds: integer(args, "seconds"),
                                   title: ToolDecision.text(args, "title"))
        guard request.duration > 0 else { return nil }
        return request
    }

    private static func integer(_ args: [String: Any], _ key: String) -> Int? {
        if let value = args[key] as? Int { return value }
        if let value = args[key] as? Double { return Int(exactly: value.rounded(.towardZero)) }
        if let value = args[key] as? String { return Int(value) }
        return nil
    }
}
