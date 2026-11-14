import GwenMobileKit

enum MessageAnswer {
    static func result(_ result: MessageSendResult, target: CallTarget, text: String, note: GroupNote) -> String {
        let who = ContactAnswer.who(target)
        switch result {
        case .sent(let direct):
            return ContactAnswer.withRemark(L.fmt2(direct ? "message_sent_direct" : "message_sent", who, text), note)
        case .cancelled: return L.fmt("message_cancelled", target.name)
        case .unavailable: return L.t("message_unavailable")
        case .needsForeground: return L.fmt("message_needs_foreground", target.name)
        case .failed(let detail): return L.fmt2("message_failed", target.name, detail)
        }
    }

    static func unresolved(_ resolution: ContactResolution, request: ContactRequest) -> String {
        ContactAnswer.unresolved(resolution, request: request, keyPrefix: "message")
    }

    static func needsText(_ request: ContactRequest) -> String {
        L.fmt("message_needs_text", ContactAnswer.asked(request))
    }
}
