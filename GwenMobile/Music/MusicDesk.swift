import Foundation

@MainActor
final class MusicDesk: ObservableObject {
    private(set) var sources: [MusicService: any MusicSource]
    private(set) var lastUsed: MusicService?

    init(sources: [MusicService: any MusicSource]? = nil) {
        self.sources = sources ?? MusicSources.live()
    }

    func runner(preferred: MusicService) -> MusicFlowRunner {
        MusicFlowRunner(sources: sources, preferred: preferred, lastUsed: lastUsed)
    }

    func remember(_ outcome: MusicFlowOutcome) {
        if outcome.soundsNow { lastUsed = outcome.service }
    }

    #if DEBUG
    private var standIn = DeskStandIn<[MusicService: any MusicSource]>()

    func stand(in stand: [MusicService: any MusicSource]) {
        standIn.stand(stand, over: &sources)
    }

    func restore() {
        standIn.restore(&sources)
    }
    #endif
}

enum MusicSources {
    @MainActor static func live() -> [MusicService: any MusicSource] {
        var found: [MusicService: any MusicSource] = [:]
        if let apple = AppleMusicSourceFactory.make() { found[.appleMusic] = apple }
        if let spotify = SpotifySourceFactory.make() { found[.spotify] = spotify }
        return found
    }
}
