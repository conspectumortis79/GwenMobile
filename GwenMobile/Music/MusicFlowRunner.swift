import GwenMobileKit

enum MusicServiceChoice {
    static func pick(_ request: MusicRequest, playing: [MusicService], lastUsed: MusicService?,
                     preferred: MusicService) -> MusicService {
        if let named = request.service { return named }
        let controls = request.action != .play || !request.wantsSomething
        guard controls else { return preferred }
        return playing.first ?? lastUsed ?? preferred
    }
}

struct MusicFlowOutcome: Equatable {
    let text: String
    let service: MusicService
    let soundsNow: Bool
    let trace: String
}

@MainActor
struct MusicFlowRunner {
    private let sources: [MusicService: any MusicSource]
    private let preferred: MusicService
    private let lastUsed: MusicService?

    init(sources: [MusicService: any MusicSource], preferred: MusicService, lastUsed: MusicService?) {
        self.sources = sources
        self.preferred = preferred
        self.lastUsed = lastUsed
    }

    func run(_ request: MusicRequest) async -> MusicFlowOutcome {
        let playing = MusicService.allCases.filter { sources[$0]?.isPlaying ?? false }
        let service = MusicServiceChoice.pick(request, playing: playing, lastUsed: lastUsed, preferred: preferred)
        guard let source = sources[service] else {
            return MusicFlowOutcome(text: MusicAnswer.text(.unsupported, service: service), service: service,
                                    soundsNow: false, trace: "dienst=\(service.rawValue) quelle=keine")
        }
        let outcome: MusicOutcome
        if request.action == .play {
            outcome = await source.play(request)
        } else {
            outcome = await source.control(request.action)
        }
        return MusicFlowOutcome(text: MusicAnswer.text(outcome, service: service), service: service,
                                soundsNow: outcome.soundsNow,
                                trace: "dienst=\(service.rawValue) laeuft=\(playing.map(\.rawValue)) "
                                    + "ergebnis=\(String(describing: outcome))")
    }
}
