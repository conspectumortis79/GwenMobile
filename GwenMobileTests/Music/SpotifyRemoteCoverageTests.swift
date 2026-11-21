@testable import GwenMobileFeatureCore
#if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
import Foundation
import SpotifyiOS
import XCTest
import GwenMobileKit

@MainActor
final class SpotifyRemoteCoverageTests: GwenTestCase {
    private func makeRemote() -> SpotifyRemote {
        let configuration = SPTConfiguration(clientID: "test-client",
                                             redirectURL: URL(string: SpotifyConfig.redirectURI)!)
        return SpotifyRemote(configuration: configuration)
    }

    func testTheRemoteReportsDisconnectedAndRefusesCommands() async {
        let remote = makeRemote()
        XCTAssertFalse(remote.isConnected)
        let play = await remote.play(uri: "spotify:track:1")
        XCTAssertFalse(play)
        for action in [MusicAction.play, .pause, .next, .previous, .resume] {
            let done = await remote.perform(action)
            XCTAssertFalse(done)
        }
        var components = URLComponents()
        components.scheme = "gwenmobile"
        components.host = "spotify-login-callback"
        let callback = components.url!
        XCTAssertFalse(remote.handle(callback))
        XCTAssertFalse(remote.handle(URL(string: "https://example.test/other")!))
        remote.shutdown()
    }

    func testAConnectionAttemptEndsInATimeout() async {
        let remote = makeRemote()
        let connected = await remote.connect(token: "token")
        XCTAssertFalse(connected)
        remote.shutdown()
    }

    func testSmokeTheDelegateCallbacksRun() {
        let remote = makeRemote()
        let configuration = SPTConfiguration(clientID: "test-client",
                                             redirectURL: URL(string: SpotifyConfig.redirectURI)!)
        let appRemote = SPTAppRemote(configuration: configuration, logLevel: .error)
        remote.appRemoteDidEstablishConnection(appRemote)
        remote.appRemote(appRemote, didFailConnectionAttemptWithError: APIError(message: "kaputt"))
        remote.appRemote(appRemote, didDisconnectWithError: nil)
        remote.shutdown()
    }
}
#endif
