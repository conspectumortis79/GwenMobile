@testable import GwenMobileFeatureCore
#if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
import Foundation
import XCTest
import GwenMobileKit

@MainActor
final class SpotifyLinkCoverageTests: GwenTestCase {
    func testTheLinkHandlesSessionsAndCallbacks() async {
        let keys = MemoryKeyStore()
        let link = SpotifyLink(clientID: { "test-client" }, keychain: keys)
        XCTAssertTrue(link.isConfigured)
        XCTAssertFalse(link.signedIn)
        XCTAssertTrue(SpotifyLink.isAvailable)
        XCTAssertFalse(link.handle(URL(string: "https://example.test/other")!))
        let callback = URL(string: SpotifyConfig.redirectURI)!
        _ = link.handle(callback)
        keys.save("session", account: SpotifyConfig.sessionAccount)
        link.signOut()
        XCTAssertFalse(link.signedIn)
        let token = await link.accessToken()
        XCTAssertNil(token)
        XCTAssertFalse(link.isConnected)
        XCTAssertFalse(link.isPlaying)
        let connected = await link.connect(token: "token")
        XCTAssertFalse(connected)
        _ = await link.play(uri: "spotify:track:1")
        _ = await link.perform(.pause)
        _ = SpotifySourceFactory.make()
    }

    func testTheLinkWithoutAClientID() {
        let keys = MemoryKeyStore()
        let link = SpotifyLink(clientID: { "   " }, keychain: keys)
        XCTAssertFalse(link.isConfigured)
        XCTAssertFalse(link.handle(URL(string: SpotifyConfig.redirectURI)!))
        _ = SpotifySourceFactory.make()
    }
}
#endif
