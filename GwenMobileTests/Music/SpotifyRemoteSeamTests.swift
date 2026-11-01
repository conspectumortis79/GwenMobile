@testable import GwenMobileFeatureCore
#if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
import Foundation
import SpotifyiOS
import XCTest
import GwenMobileKit

@MainActor
private final class FakeSpotifyApp: SpotifyAppRemoteDriving {
    var isConnected = false
    var accessToken: String?
    weak var delegate: SPTAppRemoteDelegate?
    var player: (any SpotifyPlayerDriving)?
    var connects = 0
    var disconnects = 0
    var playedURI: String?
    var token: String?
    private(set) var subscribed: SPTAppRemotePlayerStateDelegate?

    func connect() { connects += 1 }
    func disconnect() { disconnects += 1 }

    func authorizeAndPlay(uri: String, completion: @escaping @Sendable (Bool) -> Void) {
        playedURI = uri
        completion(true)
    }

    func authorizationToken(from url: URL) -> String? { token }

    func subscribeToPlayerState(_ delegate: SPTAppRemotePlayerStateDelegate) {
        subscribed = delegate
    }
}

@MainActor
private final class FakeSpotifyPlayer: SpotifyPlayerDriving {
    var answer = true
    private(set) var actions: [String] = []

    func play(_ uri: String, reply: @escaping @Sendable (Bool) -> Void) {
        actions.append("play:\(uri)")
        reply(answer)
    }

    func pause(_ reply: @escaping @Sendable (Bool) -> Void) {
        actions.append("pause")
        reply(answer)
    }

    func skipToNext(_ reply: @escaping @Sendable (Bool) -> Void) {
        actions.append("next")
        reply(answer)
    }

    func skipToPrevious(_ reply: @escaping @Sendable (Bool) -> Void) {
        actions.append("previous")
        reply(answer)
    }

    func resume(_ reply: @escaping @Sendable (Bool) -> Void) {
        actions.append("resume")
        reply(answer)
    }
}

@MainActor
final class SpotifyRemoteSeamTests: GwenTestCase {
    func testConnectStopsImmediatelyWhenConnected() async {
        let app = FakeSpotifyApp()
        app.isConnected = true
        let connected = await SpotifyRemote(appRemote: app).connect(token: "t")
        XCTAssertTrue(connected)
        XCTAssertEqual(app.connects, 0)
    }

    func testConnectWaitsForTheTimeout() async {
        let app = FakeSpotifyApp()
        let connected = await SpotifyRemote(appRemote: app).connect(token: "t")
        XCTAssertFalse(connected)
        XCTAssertEqual(app.connects, 1)
        XCTAssertEqual(app.accessToken, "t")
    }

    func testPlayAndPerformUseThePlayer() async {
        let app = FakeSpotifyApp()
        let player = FakeSpotifyPlayer()
        app.player = player
        let remote = SpotifyRemote(appRemote: app)
        let play = await remote.play(uri: "spotify:track:1")
        XCTAssertTrue(play)
        for action in [MusicAction.play, .pause, .next, .previous, .resume] {
            let done = await remote.perform(action)
            XCTAssertTrue(done)
        }
        player.answer = false
        let failed = await remote.play(uri: "spotify:track:2")
        XCTAssertFalse(failed)
        let pause = await remote.perform(.pause)
        XCTAssertFalse(pause)
        XCTAssertEqual(player.actions.first, "play:spotify:track:1")
    }

    func testPlayAndPerformWithoutAPlayerFail() async {
        let app = FakeSpotifyApp()
        let remote = SpotifyRemote(appRemote: app)
        let play = await remote.play(uri: "x")
        XCTAssertFalse(play)
        let done = await remote.perform(.pause)
        XCTAssertFalse(done)
    }

    func testWakeAndHandleUseTheToken() async {
        let app = FakeSpotifyApp()
        let remote = SpotifyRemote(appRemote: app)
        let woke = await remote.wakeAndPlay(uri: "spotify:album:1")
        XCTAssertTrue(woke)
        XCTAssertEqual(app.playedURI, "spotify:album:1")
        XCTAssertFalse(remote.handle(URL(string: "https://example.test/x")!))
        app.token = "token"
        XCTAssertTrue(remote.handle(URL(string: SpotifyConfig.redirectURI)!))
        XCTAssertEqual(app.accessToken, "token")
        XCTAssertEqual(app.connects, 1)
    }

    func testTheLifecycleCallbacks() async {
        let app = FakeSpotifyApp()
        let remote = SpotifyRemote(appRemote: app)
        let configuration = SPTConfiguration(clientID: "c", redirectURL: URL(string: SpotifyConfig.redirectURI)!)
        let real = SPTAppRemote(configuration: configuration, logLevel: .error)
        remote.appRemoteDidEstablishConnection(real)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertNotNil(app.subscribed)
        remote.appRemote(real, didFailConnectionAttemptWithError: APIError(message: "x"))
        remote.appRemote(real, didDisconnectWithError: nil)
        XCTAssertFalse(remote.isPlaying)
        app.isConnected = true
        remote.shutdown()
        XCTAssertEqual(app.disconnects, 1)
        remote.shutdown()
    }
}

@MainActor
extension SpotifyRemoteSeamTests {
    func testTheLifecycleNotificationsAndShutdown() async throws {
        let app = FakeSpotifyApp()
        let remote = SpotifyRemote(appRemote: app)
        _ = await remote.wakeAndPlay(uri: "spotify:track:1")
        app.isConnected = true
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        try await settle(200)
        XCTAssertGreaterThan(app.disconnects, 0)
        app.isConnected = false
        app.accessToken = "token"
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await settle(200)
        XCTAssertGreaterThan(app.connects, 0)
        remote.shutdown()
    }
}
#endif
