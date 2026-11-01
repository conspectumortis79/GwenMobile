@testable import GwenMobileFeatureCore
#if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
import SpotifyiOS
import XCTest
import GwenMobileKit

private final class FakePlayerAPI: NSObject, SPTAppRemotePlayerAPI, @unchecked Sendable {
    weak var delegate: SPTAppRemotePlayerStateDelegate?
    private let calls = LockedValue<[String]>([])

    var recorded: [String] { calls.current }

    nonisolated func play(_ entityIdentifier: String, callback: SPTAppRemoteCallback?) {
        calls.mutate { $0.append("play:\(entityIdentifier)") }
        callback?(nil, nil)
    }

    nonisolated func play(_ trackUri: String, asRadio: Bool, callback: @escaping SPTAppRemoteCallback) {
        calls.mutate { $0.append("radio:\(trackUri)") }
        callback(nil, nil)
    }

    nonisolated func play(_ contentItem: SPTAppRemoteContentItem, callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func play(_ contentItem: SPTAppRemoteContentItem, skipToTrackIndex index: Int,
                          callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func resume(_ callback: SPTAppRemoteCallback?) {
        calls.mutate { $0.append("resume") }
        callback?(nil, nil)
    }

    nonisolated func pause(_ callback: SPTAppRemoteCallback?) {
        calls.mutate { $0.append("pause") }
        callback?(nil, nil)
    }

    nonisolated func skip(toNext callback: SPTAppRemoteCallback?) {
        calls.mutate { $0.append("next") }
        callback?(nil, nil)
    }

    nonisolated func skip(toPrevious callback: SPTAppRemoteCallback?) {
        calls.mutate { $0.append("previous") }
        callback?(nil, nil)
    }

    nonisolated func seek(toPosition position: Int, callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func seekForward15Seconds(_ callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func seekBackward15Seconds(_ callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func setShuffle(_ shuffle: Bool, callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func setRepeatMode(_ repeatMode: SPTAppRemotePlaybackOptionsRepeatMode,
                                   callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func getPlayerState(_ callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func subscribe(toPlayerState callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func unsubscribe(toPlayerState callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func enqueueTrackUri(_ trackUri: String, callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func getAvailablePodcastPlaybackSpeeds(_ callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func getCurrentPodcastPlaybackSpeed(_ callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func setPodcastPlaybackSpeed(_ speed: SPTAppRemotePodcastPlaybackSpeed,
                                             callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }

    nonisolated func getCrossfadeState(_ callback: SPTAppRemoteCallback?) {
        callback?(nil, nil)
    }
}

private final class FakePlayerState: NSObject, SPTAppRemotePlayerState {
    var track: SPTAppRemoteTrack { fatalError("nicht benutzt") }
    var playbackPosition: Int { 0 }
    var playbackSpeed: Float { 1 }
    var isPaused: Bool { true }
    var playbackRestrictions: SPTAppRemotePlaybackRestrictions { fatalError("nicht benutzt") }
    var playbackOptions: SPTAppRemotePlaybackOptions { fatalError("nicht benutzt") }
    var contextTitle: String { "" }
    var contextURI: URL { URL(string: "spotify:context")! }
}

@MainActor
private final class FakePlayerStateDelegate: NSObject, SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {}
}

@MainActor
private final class FakeSpotifyRemoteApp: SpotifyAppRemoteDriving {
    var isConnected = false
    var accessToken: String?
    weak var delegate: SPTAppRemoteDelegate?
    var player: (any SpotifyPlayerDriving)?
    func connect() {}
    func disconnect() {}
    func authorizeAndPlay(uri: String, completion: @escaping @Sendable (Bool) -> Void) { completion(true) }
    func authorizationToken(from url: URL) -> String? { nil }
    func subscribeToPlayerState(_ delegate: SPTAppRemotePlayerStateDelegate) {}
}

@MainActor
final class SpotifyLiveWrapperTests: GwenTestCase {
    func testTheLivePlayerForwardsEveryControl() throws {
        let fake = FakePlayerAPI()
        let player = LiveSpotifyPlayer(fake)
        let replies = LockedValue<[Bool]>([])
        player.play("spotify:track:1") { ok in replies.mutate { $0.append(ok) } }
        player.pause { ok in replies.mutate { $0.append(ok) } }
        player.skipToNext { ok in replies.mutate { $0.append(ok) } }
        player.skipToPrevious { ok in replies.mutate { $0.append(ok) } }
        player.resume { ok in replies.mutate { $0.append(ok) } }
        XCTAssertEqual(fake.recorded, ["play:spotify:track:1", "pause", "next", "previous", "resume"])
        XCTAssertEqual(replies.current, [true, true, true, true, true])
    }

    func testTheLiveAppRemoteSafePaths() {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let configuration = SPTConfiguration(clientID: "gap-client",
                                             redirectURL: URL(string: SpotifyConfig.redirectURI)!)
        let remote = LiveSpotifyAppRemote(configuration: configuration)
        _ = remote.isConnected
        remote.accessToken = "token"
        XCTAssertEqual(remote.accessToken, "token")
        _ = remote.player
        _ = remote.delegate
        remote.disconnect()
        remote.connect()
        _ = remote.authorizationToken(from: URL(string: "gwenmobile://spotify?code=x")!)
        remote.subscribeToPlayerState(FakePlayerStateDelegate())
        let opened = LockedValue<Bool?>(nil)
        remote.authorizeAndPlay(uri: "spotify:track:1") { opened.set($0) }
        _ = opened.current
    }

    func testTheRemotePlayerStateChange() async {
        let fake = FakeSpotifyRemoteApp()
        let remote = SpotifyRemote(appRemote: fake)
        remote.playerStateDidChange(FakePlayerState())
        try? await settle(150)
        XCTAssertFalse(remote.isPlaying)
    }
}
#endif
