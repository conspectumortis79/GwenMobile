import GwenMobileKit
import Foundation

struct ReminderPlan: Decodable, Equatable, Sendable {
    enum Action: String, Decodable, Equatable, Sendable {
        case create, update, complete, delete, list, none
    }

    var action: Action
    var title: String?
    var due: String?
    var minutes: Int?
    var seconds: Int?
    var allDay: Bool?
    var list: String?
    var priority: String?
    var location: String?
    var proximity: String?
    var notes: String?
    var find: String?
    var repeatFrequency: String?
    var repeatInterval: Int?

    enum CodingKeys: String, CodingKey {
        case action, title, due, minutes, seconds, allDay, list, priority, location, proximity, notes, find
        case repeatFrequency = "repeat"
        case repeatInterval
    }
}

extension ReminderPlan {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        action = fields.content(Action.self, .action, fallback: .none)
        title = fields.metadata(String.self, .title)
        due = fields.metadata(String.self, .due)
        minutes = fields.metadata(Int.self, .minutes)
            ?? fields.metadata(String.self, .minutes).flatMap(Int.init)
        seconds = fields.metadata(Int.self, .seconds)
            ?? fields.metadata(String.self, .seconds).flatMap(Int.init)
        allDay = fields.metadata(Bool.self, .allDay)
        list = fields.metadata(String.self, .list)
        priority = fields.metadata(String.self, .priority)
        location = fields.metadata(String.self, .location)
        proximity = fields.metadata(String.self, .proximity)
        notes = fields.metadata(String.self, .notes)
        find = fields.metadata(String.self, .find)
        repeatFrequency = fields.metadata(String.self, .repeatFrequency)
        repeatInterval = fields.metadata(Int.self, .repeatInterval)
            ?? fields.metadata(String.self, .repeatInterval).flatMap(Int.init)
    }
}

struct ReminderRepeat: Equatable, Sendable {
    enum Frequency: String, CaseIterable, Equatable, Sendable {
        case daily, weekly, monthly, yearly
    }

    var frequency: Frequency
    var interval: Int

    init(frequency: Frequency, interval: Int = 1) {
        self.frequency = frequency
        self.interval = max(1, interval)
    }

    init?(word: String?, interval: Int?) {
        guard let cleaned = word?.trimmed.lowercased(),
              let frequency = Frequency(rawValue: cleaned) else { return nil }
        self.init(frequency: frequency, interval: interval ?? 1)
    }
}

struct ReminderPlace: Equatable, Sendable {
    enum Proximity: String, Equatable, Sendable {
        case arrive, leave
    }

    var name: String
    var proximity: Proximity
}

enum ReminderPriority: String, Equatable, Sendable {
    case high, low

    var ekPriority: Int {
        switch self {
        case .high: return 1
        case .low: return 9
        }
    }
}

struct ReminderRequest: Equatable, Sendable {
    enum Action: String, Equatable, Sendable {
        case create, update, complete, delete, list
    }

    var action: Action
    var title: String
    var find: String
    var due: Date?
    var allDay: Bool
    var list: String?
    var repeatRule: ReminderRepeat?
    var priority: ReminderPriority?
    var place: ReminderPlace?
    var notes: String?
    var minutes: Int?
    var seconds: Int?

    var stepWords: String {
        StepWords.joined(action.rawValue, title, find, due.map(Formatters.eventDateTime), list, place?.name)
    }

    init?(plan: ReminderPlan, now: Date = Date()) {
        guard let action = Action(rawValue: plan.action.rawValue) else { return nil }
        let namedDue = plan.due.flatMap { Formatters.eventDate(from: $0) ?? Formatters.eventDay(from: $0) }
        let secondsDue = plan.seconds.flatMap { $0 > 0 ? now.addingTimeInterval(Double($0)) : nil }
        let relativeDue = secondsDue ?? plan.minutes.flatMap { $0 > 0 ? now.addingTimeInterval(Double($0) * 60) : nil }
        let due = namedDue ?? relativeDue
        let title = plan.title?.trimmed ?? ""
        self.action = action
        self.title = title.isEmpty && action == .create
            ? ((plan.minutes ?? 0) > 0 || (plan.seconds ?? 0) > 0
                ? L.t("rem_default_timer") : L.t("rem_default_title"))
            : title
        self.find = Self.text(plan.find) ?? title
        self.due = due
        self.allDay = due != nil && (plan.allDay ?? Self.isDayOnly(plan.due))
        self.list = Self.text(plan.list)
        self.repeatRule = ReminderRepeat(word: plan.repeatFrequency, interval: plan.repeatInterval)
        self.priority = plan.priority.flatMap { ReminderPriority(rawValue: $0.lowercased()) }
        if let name = Self.text(plan.location) {
            let proximity = plan.proximity.flatMap { ReminderPlace.Proximity(rawValue: $0.lowercased()) } ?? .arrive
            self.place = ReminderPlace(name: name, proximity: proximity)
        }
        self.notes = Self.text(plan.notes)
        self.minutes = plan.minutes.flatMap { $0 > 0 ? $0 : nil }
        self.seconds = plan.seconds.flatMap { $0 > 0 ? $0 : nil }
    }

    private static func text(_ value: String?) -> String? {
        let trimmed = value?.trimmed ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isDayOnly(_ value: String?) -> Bool {
        guard let trimmed = value?.trimmed else { return false }
        return !trimmed.contains(":")
    }
}

enum ReminderMerge {
    static func merged(_ routed: ReminderRequest, with whole: ReminderRequest) -> ReminderRequest {
        var kept = routed
        let defaults = [L.t("rem_default_title"), L.t("rem_default_timer")]
        if kept.title.isEmpty || defaults.contains(kept.title) {
            if !whole.title.isEmpty, !defaults.contains(whole.title) { kept.title = whole.title }
        }
        if kept.find.trimmed.isEmpty || kept.find == routed.title { kept.find = whole.find }
        if kept.due == nil, let due = whole.due {
            kept.due = due
            kept.allDay = whole.allDay
        }
        if kept.list == nil, kept.place == nil { kept.list = whole.list }
        if kept.repeatRule == nil { kept.repeatRule = whole.repeatRule }
        if kept.priority == nil { kept.priority = whole.priority }
        if kept.place == nil { kept.place = whole.place }
        if kept.notes == nil { kept.notes = whole.notes }
        if kept.minutes == nil { kept.minutes = whole.minutes }
        if kept.seconds == nil { kept.seconds = whole.seconds }
        return kept
    }

}
