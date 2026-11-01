import GwenMobileKit
import Foundation

typealias CalendarChipOutcome = ChipOutcome<CalendarRef>

extension CalendarRef: ChipRef {
    var chipID: String { eventID }
}

enum CalendarChip {
    @MainActor
    static func outcome(for ref: CalendarRef, hasAccess: Bool,
                        isLive: @MainActor (String) -> Bool) -> CalendarChipOutcome {
        ChipGate.outcome(for: ref, hasAccess: hasAccess, isLive: isLive)
    }

    static func noticeKey(for outcome: CalendarChipOutcome) -> String? {
        switch outcome {
        case .present:
            return nil
        case .accessMissing:
            return "cal_denied"
        case .gone:
            return "cal_chip_gone"
        }
    }

    static var todayURL: URL? { URL(string: "calshow://") }
}
