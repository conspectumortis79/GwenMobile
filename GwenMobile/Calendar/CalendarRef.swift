import GwenMobileKit
import Foundation

struct CalendarRef: Codable, Hashable, Sendable, Identifiable {
    var eventID: String
    var title: String
    var start: Date

    enum CodingKeys: String, CodingKey {
        case eventID, title, start
    }
}

extension CalendarRef {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        eventID = fields.content(String.self, .eventID, fallback: "")
        title = fields.content(String.self, .title, fallback: "")
        start = fields.metadata(Date.self, .start, fallback: Date(timeIntervalSince1970: 0))
    }
}

extension CalendarRef {
    var id: String { eventID }
    var isOpenable: Bool { !eventID.isEmpty }
    var chipStamp: String { Formatters.eventChip(start) }
    var chipTitle: String { title.isEmpty ? L.t("cal_default_title") : title }

    #if DEBUG
    var logSummary: String { "\(chipTitle)@\(eventID.prefix(8))" }
    #endif
}

struct CalendarOutcome: Equatable, Sendable {
    var notice: String
    var ref: CalendarRef?
}
