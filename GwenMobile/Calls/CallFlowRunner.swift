import GwenMobileKit

struct CallFlowOutcome: Equatable {
    let text: String
    let placed: Bool
    let trace: String
}

@MainActor
struct CallFlowRunner {
    private let directory: any ContactDirectory
    private let dialer: any CallPlacing

    init(directory: any ContactDirectory, dialer: any CallPlacing) {
        self.directory = directory
        self.dialer = dialer
    }

    func run(_ request: ContactRequest) async -> CallFlowOutcome {
        let lookup = await ContactLookup(directory: directory).resolve(request)
        guard case .resolved(let resolution, let cards) = lookup else {
            return CallFlowOutcome(text: ContactAnswer.lookupFailed(lookup), placed: false, trace: lookup.trace)
        }
        guard case .unique(let target, let note) = resolution else {
            return CallFlowOutcome(text: CallAnswer.unresolved(resolution, request: request), placed: false,
                                   trace: lookup.trace)
        }
        let start = await dialer.place(target.number)
        return CallFlowOutcome(text: CallAnswer.started(start, target: target, note: note),
                               placed: start != .failed,
                               trace: "karten=\(cards) ziel=\(target.name) nummer=\(target.number.masked) "
                                   + "weg=\(dialer.way) start=\(start.rawValue)")
    }
}
