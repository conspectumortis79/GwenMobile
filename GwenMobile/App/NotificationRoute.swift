import GwenMobileKit
import Foundation

enum NotificationRoute {
    static let key = "gwen.route"
    static let dayKey = "gwen.briefing.day"
    static let dateKey = "gwen.briefing.date"
    static let briefing = "briefing"

    static func briefingInfo(day: BriefingDay, date: String) -> [String: String] {
        [key: briefing, dayKey: day.rawValue, dateKey: date]
    }

    static func briefingDay(in userInfo: [AnyHashable: Any], now: Date = Date()) -> BriefingDay? {
        guard userInfo[key] as? String == briefing else { return nil }
        if let stamp = userInfo[dateKey] as? String, let target = Formatters.eventDay(from: stamp) {
            return BriefingDay.between(now, and: target) ?? .today
        }
        return (userInfo[dayKey] as? String).flatMap(BriefingDay.init(rawValue:)) ?? .today
    }
}

@MainActor
final class BriefingOpenRequests: ObservableObject {
    static let shared = BriefingOpenRequests()

    @Published private(set) var token = 0
    @Published private(set) var day = BriefingDay.today

    func ask(day: BriefingDay) {
        flowMark("BRIEFING mitteilung geoeffnet tag=\(day.rawValue)")
        self.day = day
        token += 1
    }
}
