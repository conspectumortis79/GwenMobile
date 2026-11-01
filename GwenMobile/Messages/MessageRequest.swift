import GwenMobileKit

struct MessageRequest: Equatable, Sendable {
    var recipient: ContactRequest
    var text: String
    var needsReview = false

    var stepWords: String { StepWords.joined(recipient.stepWords, text) }

    static func from(_ args: [String: Any]) -> MessageRequest? {
        guard var recipient = ContactRequest.from(args) else { return nil }
        recipient.numberKind = .mobile
        return MessageRequest(recipient: recipient, text: ToolDecision.text(args, "text") ?? "")
    }
}
