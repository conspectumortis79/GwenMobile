import GwenMobileKit
import Foundation

struct ScanReminderOffer: Codable, Equatable, Hashable, Sendable {
    var title: String
    var due: Date?
    var allDay: Bool = false
    var list: String? = nil
    var notes: String? = nil

    enum CodingKeys: String, CodingKey {
        case title, due, allDay, list, notes
    }
}

extension ScanReminderOffer {
    init?(from request: ReminderRequest) {
        let title = request.title.trimmed
        guard request.action == .create, !title.isEmpty, let due = request.due else { return nil }
        self.init(title: title, due: due, allDay: request.allDay, list: request.list, notes: request.notes)
    }

    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        title = fields.content(String.self, .title, fallback: "")
        due = fields.metadata(Date.self, .due)
        allDay = fields.metadata(Bool.self, .allDay, fallback: false)
        list = fields.metadata(String.self, .list)
        notes = fields.metadata(String.self, .notes)
    }

    var isUsable: Bool {
        !title.trimmed.isEmpty && due != nil
    }

    var request: ReminderRequest? {
        guard let due, isUsable else { return nil }
        let plan = ReminderPlan(action: .create, title: title, due: Formatters.eventDateTime(due),
                                minutes: nil, seconds: nil, allDay: allDay, list: list,
                                priority: nil, location: nil, proximity: nil, notes: notes,
                                find: nil, repeatFrequency: nil, repeatInterval: nil)
        return ReminderRequest(plan: plan)
    }

    var chipStamp: String? {
        guard let due else { return nil }
        return allDay ? Formatters.day(due) : Formatters.eventChip(due)
    }
}
