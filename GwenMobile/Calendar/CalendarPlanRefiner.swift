import GwenMobileKit
import Foundation

enum CalendarPlanRefiner {

    static func keepAction(_ routed: QwenAPI.CalendarPlan?, filledBy planner: QwenAPI.CalendarPlan?,
                           targetExists: Bool) -> QwenAPI.CalendarPlan? {
        guard let routed, routed.action == .create else { return planner ?? routed }
        guard let planner else { return routed }
        guard planner.action != .create else { return planner }
        if targetExists { return planner }
        var made = planner
        made.action = .create
        made.find = nil
        if made.title?.isEmpty != false { made.title = routed.title }
        if made.start?.isEmpty != false { made.start = routed.start }
        return made
    }

    static func sameAppointment(_ left: String, _ right: String) -> Bool {
        func bare(_ text: String) -> String {
            text.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
        }
        let a = bare(left), b = bare(right)
        return !a.isEmpty && !b.isEmpty && a == b
    }
}
