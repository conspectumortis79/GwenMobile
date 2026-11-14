import Foundation

enum ScanPlan {
    static func analysisActions(_ plan: SendPlan, remind: Bool) -> [ToolDecision] {
        var actions = plan.actions.filter { $0.stepKind != .scan }
        if remind { actions = actions.filter { $0.stepKind != .reminder } }
        if actions.isEmpty { return [ToolDecision(route: .chat)] }
        return actions
    }
}
