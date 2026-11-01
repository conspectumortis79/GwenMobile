import GwenMobileKit
import Foundation

enum WeatherDayTabs {
    static func dates(selected: String, today: Date = Date(),
                      calendar: Calendar = .current) -> [String] {
        let todayStart = calendar.startOfDay(for: today)
        let offset = max(0, offset(of: selected, today: today, calendar: calendar))
        let clamped = calendar.date(byAdding: .day, value: offset, to: todayStart)!
        var days: [Date] = []
        if offset <= 2 {
            for step in 0...2 {
                if let date = calendar.date(byAdding: .day, value: step, to: todayStart) { days.append(date) }
            }
        } else {
            days.append(todayStart)
            days.append(clamped)
            if let next = calendar.date(byAdding: .day, value: 1, to: clamped) { days.append(next) }
        }
        var seen = Set<String>()
        return days.map(stamp).filter { seen.insert($0).inserted }
    }

    static func offset(of dateString: String, today: Date = Date(), calendar: Calendar = .current) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        guard let date = Formatters.eventDay(from: dateString).map({ calendar.startOfDay(for: $0) }) else {
            return 0
        }
        return calendar.dateComponents([.day], from: todayStart, to: date).day!
    }

    static func stamp(_ date: Date) -> String { Formatters.stamp(date) }
}
