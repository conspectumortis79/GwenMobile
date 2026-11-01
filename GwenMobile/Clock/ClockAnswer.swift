import GwenMobileKit
import Foundation

enum ClockAnswer {
    static func text(now: Date, request: ClockRequest, home: TimeZone = .current) -> String {
        let zone = request.zone ?? home
        let time = render(now, zone: zone, date: .none, time: .short)
        let day = render(now, zone: zone, date: .full, time: .none)
        let line = request.zone == nil
            ? L.fmt("clock_here", time)
            : L.fmt2("clock_there", request.placeName ?? zone.identifier, time)
        return line + " — " + day + "."
    }

    static func render(_ date: Date, zone: TimeZone, date dateStyle: DateFormatter.Style,
                       time timeStyle: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.locale = L.lang.locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }
}
