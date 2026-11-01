import GwenMobileKit
import Foundation

struct MessageFlowOutcome: Equatable {
    let text: String
    let trace: String
    var sent = false
}

@MainActor
struct MessageFlowRunner {
    private let directory: any ContactDirectory
    private let sender: any MessageSending
    private let reviewer: any MessageSending

    init(directory: any ContactDirectory, sender: any MessageSending, reviewer: any MessageSending) {
        self.directory = directory
        self.sender = sender
        self.reviewer = reviewer
    }

    func run(_ request: MessageRequest) async -> MessageFlowOutcome {
        let body = request.text.trimmed
        guard !body.isEmpty else {
            return MessageFlowOutcome(text: MessageAnswer.needsText(request.recipient), trace: "text=leer")
        }
        let lookup = await ContactLookup(directory: directory).resolve(request.recipient)
        guard case .resolved(let resolution, let cards) = lookup else {
            return MessageFlowOutcome(text: ContactAnswer.lookupFailed(lookup), trace: lookup.trace)
        }
        guard case .unique(let target, let note) = resolution else {
            return MessageFlowOutcome(text: MessageAnswer.unresolved(resolution, request: request.recipient),
                                      trace: lookup.trace)
        }
        let way = request.needsReview ? reviewer : sender
        let result = await way.send(body, to: target.number)
        return MessageFlowOutcome(text: MessageAnswer.result(result, target: target, text: body, note: note),
                                  trace: "karten=\(cards) ziel=\(target.name) nummer=\(target.number.masked) "
                                      + "zeichen=\(body.count) weg=\(way.way) pruefen=\(request.needsReview) "
                                      + "ergebnis=\(result.trace)",
                                  sent: result.isSent)
    }
}
