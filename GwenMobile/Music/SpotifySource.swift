import GwenMobileKit
import Foundation

@MainActor
protocol SpotifyAuthorizing {
    var isConfigured: Bool { get }
    func accessToken() async -> String?
}

@MainActor
protocol SpotifyRemoteControlling {
    var isConnected: Bool { get }
    var isPlaying: Bool { get }
    func connect(token: String) async -> Bool
    func play(uri: String) async -> Bool
    func perform(_ action: MusicAction) async -> Bool
    func wakeAndPlay(uri: String) async -> Bool
}

enum SpotifyWay: Equatable {
    case remote
    case connectFirst
    case web

    static func pick(connected: Bool, active: Bool) -> SpotifyWay {
        if connected { return .remote }
        return active ? .connectFirst : .web
    }
}

@MainActor
final class SpotifySource: MusicSource {
    private let auth: any SpotifyAuthorizing
    private let remote: any SpotifyRemoteControlling
    private let web: any SpotifyWebControlling
    private let isActive: @MainActor () -> Bool

    init(auth: any SpotifyAuthorizing, remote: any SpotifyRemoteControlling, web: any SpotifyWebControlling,
         isActive: @escaping @MainActor () -> Bool) {
        self.auth = auth
        self.remote = remote
        self.web = web
        self.isActive = isActive
    }

    var isPlaying: Bool { remote.isPlaying }

    func play(_ request: MusicRequest) async -> MusicOutcome {
        guard auth.isConfigured else { return .notSetUp }
        guard let token = await auth.accessToken() else { return .notConnected }
        var target: SpotifyTarget?
        if request.wantsSomething {
            do {
                target = try await web.find(request, token: token)
            } catch {
                return .failed(TextLine.oneLine(error.localizedDescription, limit: 120))
            }
            guard target != nil else { return .notFound(request.term) }
        }
        let started = target.map { MusicOutcome.playing($0.pick) } ?? .resumed
        switch SpotifyWay.pick(connected: remote.isConnected, active: isActive()) {
        case .remote:
            return await playRemotely(target) ? started : .failed(L.t("music_spotify_refused"))
        case .connectFirst:
            if await remote.connect(token: token) {
                return await playRemotely(target) ? started : .failed(L.t("music_spotify_refused"))
            }
            return await remote.wakeAndPlay(uri: target?.uri ?? "") ? .openedApp(target?.pick)
                : .failed(L.t("music_spotify_missing_app"))
        case .web:
            return await webOutcome({ try await self.web.play(target, token: token) }, success: started)
        }
    }

    func control(_ action: MusicAction) async -> MusicOutcome {
        guard auth.isConfigured else { return .notSetUp }
        guard let token = await auth.accessToken() else { return .notConnected }
        let done: MusicOutcome = action == .resume || action == .play ? .resumed : .controlled(action)
        switch SpotifyWay.pick(connected: remote.isConnected, active: isActive()) {
        case .remote:
            return await remote.perform(action) ? done : .failed(L.t("music_spotify_refused"))
        case .connectFirst:
            if await remote.connect(token: token), await remote.perform(action) { return done }
            return await webOutcome({ try await self.web.perform(action, token: token) }, success: done)
        case .web:
            return await webOutcome({ try await self.web.perform(action, token: token) }, success: done)
        }
    }

    private func playRemotely(_ target: SpotifyTarget?) async -> Bool {
        guard let target else { return await remote.perform(.resume) }
        return await remote.play(uri: target.uri)
    }

    private func webOutcome(_ call: () async throws -> SpotifyWebResult, success: MusicOutcome) async -> MusicOutcome {
        do {
            switch try await call() {
            case .done: return success
            case .refused(let message): return .failed(message)
            }
        } catch {
            return .failed(TextLine.oneLine(error.localizedDescription, limit: 120))
        }
    }
}
