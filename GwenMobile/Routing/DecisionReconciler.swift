enum DecisionReconciler {
    static func runs(in decisions: [ToolDecision],
                     continuingWhen continues: (ToolDecision, ToolDecision) -> Bool) -> [[Int]] {
        var runs: [[Int]] = []
        var index = 0
        while index < decisions.count {
            var end = index
            while end + 1 < decisions.count, continues(decisions[end], decisions[end + 1]) {
                end += 1
            }
            runs.append(Array(index...end))
            index = end + 1
        }
        return runs
    }

    static func applying(_ decisions: [ToolDecision], runs: [[Int]],
                         replacing build: ([Int]) async -> [ToolDecision]?) async -> [ToolDecision] {
        guard !runs.isEmpty else { return decisions }
        var replacements: [Int: [ToolDecision]] = [:]
        for run in runs {
            guard let fresh = await build(run), !fresh.isEmpty else { continue }
            replacements[run[0]] = fresh
        }
        guard !replacements.isEmpty else { return decisions }
        var result: [ToolDecision] = []
        var index = 0
        while index < decisions.count {
            if let fresh = replacements[index], let run = runs.first(where: { $0[0] == index }) {
                result.append(contentsOf: fresh)
                index += run.count
            } else {
                result.append(decisions[index])
                index += 1
            }
        }
        return result
    }
}
