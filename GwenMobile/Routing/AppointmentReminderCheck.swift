import GwenMobileKit
import Foundation

enum AppointmentReminderCheck {
    static let hint = PromptLibrary.text("check_appointment_reminder")

    static func groups(in decisions: [ToolDecision]) -> [[Int]] {
        DecisionReconciler.runs(in: decisions, continuingWhen: { ($0.wish ?? "") == ($1.wish ?? "") })
            .filter { run in
                let kinds = Set(run.map { decisions[$0].stepKind })
                return kinds.contains(.calendar) && kinds.contains(.reminder)
            }
    }

    static func reconciled(_ decisions: [ToolDecision], message: String,
                           asking ask: (_ wish: String, _ hint: String) async -> [ToolDecision]?)
        async -> [ToolDecision] {
        await DecisionReconciler.applying(decisions, runs: groups(in: decisions)) { run in
            let wish = decisions[run[0]].wish
            return await ask(wish ?? message, hint)?.map { fresh in
                var kept = fresh
                kept.wish = wish
                return kept
            }
        }
    }
}
