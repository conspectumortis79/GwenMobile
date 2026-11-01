import GwenMobileKit
import Foundation

enum PictureChainCheck {
    static let hint = PromptLibrary.text("check_picture_chain")
    static let pictureKinds: Set<SendStepKind> = [.create, .edit]

    static func groups(in decisions: [ToolDecision]) -> [[Int]] {
        DecisionReconciler.runs(in: decisions, continuingWhen: {
            pictureKinds.contains($0.stepKind) && pictureKinds.contains($1.stepKind)
        }).filter { run in
            run.count > 1
                && !run.contains(where: { decisions[$0].pictureMonochrome })
        }
    }

    static func reconciled(_ decisions: [ToolDecision], message: String,
                           asking ask: @Sendable (_ text: String, _ hint: String) async -> [ToolDecision]?)
        async -> [ToolDecision] {
        await DecisionReconciler.applying(decisions, runs: groups(in: decisions)) { run in
            let words = run.compactMap { decisions[$0].wish }.joined(separator: "\n").trimmed
            let wish = words.isEmpty ? message : words
            guard let fresh = await ask(message, hint) else { return nil }
            let pictures = fresh.filter { pictureKinds.contains($0.stepKind) }
            guard pictures.count == 1 else { return nil }
            let startsFresh = run.contains { decisions[$0].stepKind == .create }
            guard pictures[0].stepKind == (startsFresh ? .create : .edit) else { return nil }
            var made = pictures[0]
            made.wish = wish
            return [made]
        }
    }
}
