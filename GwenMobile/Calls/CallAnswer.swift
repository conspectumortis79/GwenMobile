import GwenMobileKit

enum CallAnswer {
    static func started(_ start: CallStart, target: CallTarget, note: GroupNote) -> String {
        let who = ContactAnswer.who(target)
        switch start {
        case .dialing: return ContactAnswer.withRemark(L.fmt("call_dialing", who), note)
        case .confirming: return ContactAnswer.withRemark(L.fmt("call_confirming", who), note)
        case .failed: return ContactAnswer.withRemark(L.fmt("call_failed", target.name), note)
        }
    }

    static func unresolved(_ resolution: ContactResolution, request: ContactRequest) -> String {
        ContactAnswer.unresolved(resolution, request: request, keyPrefix: "call")
    }
}
