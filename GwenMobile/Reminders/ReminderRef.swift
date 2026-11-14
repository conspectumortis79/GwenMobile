import GwenMobileKit
import Foundation

struct ReminderRef: Codable, Hashable, Sendable, Identifiable {
    var reminderID: String
    var title: String
    var list: String
    var due: Date?
    var allDay: Bool
    var place: String?

    enum CodingKeys: String, CodingKey {
        case reminderID, title, list, due, allDay, place
    }
}

extension ReminderRef {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        reminderID = fields.content(String.self, .reminderID, fallback: "")
        title = fields.content(String.self, .title, fallback: "")
        list = fields.content(String.self, .list, fallback: "")
        due = fields.metadata(Date.self, .due)
        allDay = fields.metadata(Bool.self, .allDay, fallback: false)
        place = fields.metadata(String.self, .place)
    }

    init(_ reminder: StoredReminder) {
        reminderID = reminder.id
        title = reminder.title
        list = reminder.list
        due = reminder.due
        allDay = reminder.allDay
        place = reminder.place
    }
}

extension ReminderRef {
    var id: String { reminderID }
    var isOpenable: Bool { !reminderID.isEmpty }
    var chipTitle: String { title.isEmpty ? L.t("rem_default_title") : title }

    var chipStamp: String {
        if let due { return allDay ? Formatters.day(due) : Formatters.eventChip(due) }
        if let place, !place.isEmpty { return place }
        return list
    }
}

typealias ReminderChipOutcome = ChipOutcome<ReminderRef>

extension ReminderRef: ChipRef {
    var chipID: String { reminderID }
}

enum ReminderChip {
    @MainActor
    static func outcome(for ref: ReminderRef, hasAccess: Bool,
                        isLive: @MainActor (String) -> Bool) -> ReminderChipOutcome {
        ChipGate.outcome(for: ref, hasAccess: hasAccess, isLive: isLive)
    }

    static func noticeKey(for outcome: ReminderChipOutcome) -> String? {
        switch outcome {
        case .present: return nil
        case .accessMissing: return "rem_denied"
        case .gone: return "rem_chip_gone"
        }
    }

    static var remindersURLs: [URL] {
        ["x-apple-reminderkit://", "x-apple-reminder://"].compactMap { URL(string: $0) }
    }
}
