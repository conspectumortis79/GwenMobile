import GwenMobileKit

enum AnswerLengthPlan {
    static func fitting(_ history: [ChatMessage], detailWish: Bool) -> AnswerLength {
        guard detailWish, let asked = history.lastIndex(where: { $0.role == .user }) else { return .compact }
        let previous = history[..<asked].last { $0.role == .assistant }?.text ?? ""
        return .detailed(items: AnswerItems.count(in: previous))
    }
}
