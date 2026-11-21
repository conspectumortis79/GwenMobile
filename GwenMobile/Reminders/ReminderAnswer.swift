import GwenMobileKit
import Foundation

enum ReminderAnswer {
    static func created(_ reminder: StoredReminder) -> String {
        L.fmt("rem_created", describe(reminder))
    }

    static func updated(_ reminder: StoredReminder) -> String {
        L.fmt("rem_updated", describe(reminder))
    }

    static func completed(_ reminder: StoredReminder) -> String {
        L.fmt("rem_completed", reminder.title)
    }

    static func deleted(_ reminder: StoredReminder) -> String {
        L.fmt("rem_deleted", reminder.title)
    }

    static func notFound(_ request: ReminderRequest) -> String {
        let words = [request.find, request.title]
            .map { $0.trimmed }
            .first { !$0.isEmpty } ?? ""
        return L.t("rem_not_found") + words
    }

    static func list(_ reminders: [StoredReminder], titled title: String?) -> String {
        let head = title.map { L.fmt("rem_list_head", $0) } ?? L.t("rem_list_head_all")
        guard !reminders.isEmpty else {
            let line = title.map { L.fmt("rem_list_empty", $0) } ?? L.t("rem_list_empty_all")
            return head + "\n" + line
        }
        let lines = reminders.map { reminder -> String in
            var parts = [reminder.title]
            if let due = reminder.due {
                parts.append("⏰ " + (reminder.allDay ? Formatters.day(due) : Formatters.eventStart(due)))
            }
            if let place = reminder.place {
                parts.append("📍 " + place)
            }
            return "- " + parts.joined(separator: " — ")
        }
        return ([head] + lines).joined(separator: "\n")
    }

    static func describe(_ reminder: StoredReminder) -> String {
        var lines = [reminder.title]
        if let due = reminder.due {
            lines.append(L.fmt("rem_due_line", reminder.allDay ? Formatters.day(due) : Formatters.eventStart(due)))
        }
        if !reminder.list.isEmpty {
            lines.append(L.fmt("rem_list_line", reminder.list))
        }
        if let place = reminder.placeDescription {
            lines.append(L.fmt("rem_place_line", place))
        }
        if let rule = reminder.repeatRule {
            lines.append(L.fmt("rem_repeat_line", repeatText(rule)))
        }
        if reminder.priority == .high {
            lines.append(L.t("rem_priority_line"))
        }
        if !reminder.notes.isEmpty {
            lines.append(reminder.notes)
        }
        return lines.joined(separator: "\n")
    }

    static func repeatText(_ rule: ReminderRepeat) -> String {
        if rule.interval == 1 {
            switch rule.frequency {
            case .daily: return L.t("rem_repeat_daily")
            case .weekly: return L.t("rem_repeat_weekly")
            case .monthly: return L.t("rem_repeat_monthly")
            case .yearly: return L.t("rem_repeat_yearly")
            }
        }
        switch rule.frequency {
        case .daily: return L.n("rem_repeat_every_days", rule.interval)
        case .weekly: return L.n("rem_repeat_every_weeks", rule.interval)
        case .monthly: return L.n("rem_repeat_every_months", rule.interval)
        case .yearly: return L.n("rem_repeat_every_years", rule.interval)
        }
    }
}
