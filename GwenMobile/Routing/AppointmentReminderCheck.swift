import GwenMobileKit
import Foundation

enum AppointmentReminderCheck {
    static let hint = PromptLibrary.text("check_appointment_reminder")
    private static let maxNotificationMinutes = 7 * 24 * 60.0

    static func groups(in decisions: [ToolDecision]) -> [[Int]] {
        DecisionReconciler.runs(in: decisions, continuingWhen: continues)
            .filter { run in
                let kinds = Set(run.map { decisions[$0].stepKind })
                return kinds.contains(.calendar) && kinds.contains(.reminder)
            }
    }

    static func reconciled(_ decisions: [ToolDecision], message: String,
                           asking ask: (_ wish: String, _ hint: String) async -> [ToolDecision]?)
        async -> [ToolDecision] {
        await DecisionReconciler.applying(decisions, runs: groups(in: decisions)) { run in
            let wish = wishText(decisions, run: run)
            return await ask(wish ?? message, hint)?.map { fresh in
                var kept = fresh
                kept.wish = wish
                return kept
            }
        }
    }

    private static func continues(_ current: ToolDecision, _ next: ToolDecision) -> Bool {
        if (current.wish ?? "") == (next.wish ?? "") { return true }
        if current.stepKind == .calendar, let calendar = current.calendarPlan,
           case .reminder(let reminder) = next.route {
            return notification(calendar, reminder)
        }
        if case .reminder(let reminder) = current.route,
           next.stepKind == .calendar, let calendar = next.calendarPlan {
            return notification(calendar, reminder)
        }
        return false
    }

    private static func notification(_ calendar: QwenAPI.CalendarPlan,
                                     _ reminder: ReminderRequest) -> Bool {
        guard calendar.action == .create, reminder.action == .create,
              !reminder.allDay, reminder.place == nil, reminder.repeatRule == nil,
              reminder.priority == nil, let start = calendar.startDate, let due = reminder.due,
              due <= start else { return false }
        guard let title = calendar.title?.trimmed, !title.isEmpty,
              CalendarPlanRefiner.sameAppointment(title, reminder.title) else { return false }
        let minutes = start.timeIntervalSince(due) / 60
        return minutes >= 0 && minutes <= maxNotificationMinutes
    }

    private static func wishText(_ decisions: [ToolDecision], run: [Int]) -> String? {
        var seen = Set<String>()
        let wishes = run.compactMap { decisions[$0].wish?.trimmed }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return wishes.isEmpty ? nil : wishes.joined(separator: "\n")
    }
}
