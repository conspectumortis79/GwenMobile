import Foundation

enum ChainSchedule {
    static let inFlight = WishRouting.inFlight
    static let stagger = WishRouting.stagger

    static func stages(_ steps: [ToolDecision], limit: Int = inFlight) -> [[Int]] {
        let most = max(1, limit)
        guard most > 1 else { return steps.indices.map { [$0] } }
        var stages: [[Int]] = []
        var together: [Int] = []
        var waiting: [Int] = []

        func closePhase() {
            var group: [Int] = []
            for index in together {
                group.append(index)
                guard group.count >= most else { continue }
                stages.append(group)
                group = []
            }
            if !group.isEmpty { stages.append(group) }
            for index in waiting { stages.append([index]) }
            together = []
            waiting = []
        }

        for (index, step) in steps.enumerated() {
            guard runsConcurrently(step) else {
                waiting.append(index)
                if case .history = step.route { closePhase() }
                continue
            }
            together.append(index)
        }
        closePhase()
        return stages
    }

    static func runsConcurrently(_ step: ToolDecision) -> Bool {
        guard step.standalone else { return false }
        return runsConcurrently(step.stepKind, translatesFromChat: step.translatesFromChat)
    }

    static func runsConcurrently(_ kind: SendStepKind, translatesFromChat: Bool) -> Bool {
        switch kind {
        case .chat, .search, .gallery, .code, .weather, .clock, .price, .briefing, .status, .create:
            return true
        case .translate:
            return !translatesFromChat
        case .calendar, .reminder, .timer, .readAloud, .readAnswer, .place, .route, .priceWatch,
             .call, .music, .message, .memory, .history, .scan, .edit, .video:
            return false
        }
    }
}

extension ToolDecision {
    var translatesFromChat: Bool {
        guard case .translate(let job) = route else { return false }
        return job.fromChat
    }
}
