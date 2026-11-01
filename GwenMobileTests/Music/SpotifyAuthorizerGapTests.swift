@testable import GwenMobileFeatureCore
#if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
import ObjectiveC
import SpotifyiOS
import XCTest
import GwenMobileKit

@MainActor
private func makeSpotifySession(token: String, refresh: String = "refresh",
                                expiresIn: TimeInterval) -> SPTSession? {
    let selector = NSSelectorFromString("initWithAccessToken:refreshToken:expirationDate:scope:")
    guard let method = class_getInstanceMethod(SPTSession.self, selector) else { return nil }
    typealias InitIMP = @convention(c) (AnyObject, Selector, NSString, NSString, NSDate, UInt) -> AnyObject?
    let function = unsafeBitCast(method_getImplementation(method), to: InitIMP.self)
    let instance = class_createInstance(SPTSession.self, 0) as AnyObject
    let raw = function(instance, selector, token as NSString, refresh as NSString,
                       Date().addingTimeInterval(expiresIn) as NSDate, 0)
    return raw as? SPTSession
}

@MainActor
final class SpotifyAuthorizerGapTests: GwenTestCase {
    private func configuration() -> SPTConfiguration {
        SPTConfiguration(clientID: "gap-client", redirectURL: URL(string: SpotifyConfig.redirectURI)!)
    }

    func testTheAuthorizerStoresAndRenewsSessions() async throws {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let store = MemoryKeyStore()
        let changes = LockedValue(0)
        let manager = SPTSessionManager(configuration: configuration(), delegate: nil)
        let authorizer = SpotifyAuthorizer(configuration: configuration(), store: store,
                                           changed: { changes.mutate { $0 += 1 } })
        authorizer.sessionManager(manager: manager, didInitiate: try XCTUnwrap(
            makeSpotifySession(token: "live-token", expiresIn: 3600)))
        try await settle(300)
        let live = await authorizer.accessToken()
        XCTAssertEqual(live, "live-token")
        XCTAssertGreaterThan(changes.current, 0)

        authorizer.sessionManager(manager: manager, didInitiate: try XCTUnwrap(
            makeSpotifySession(token: "alter-token", expiresIn: -60)))
        try await settle(300)
        authorizer.sessionManager(manager: manager, didRenew: try XCTUnwrap(
            makeSpotifySession(token: "neuer-token", expiresIn: 3600)))
        try await settle(300)

        authorizer.sessionManager(manager: manager, didFailWith: APIError(message: "kaputt"))
        try await settle(200)
        _ = SpotifyAuthorizer.archive(try XCTUnwrap(makeSpotifySession(token: "x", expiresIn: 60)))
    }

    func testTheAuthorizerBeginsAndRenewsAnExpiredSession() async throws {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let store = MemoryKeyStore()
        let manager = SPTSessionManager(configuration: configuration(), delegate: nil)
        let authorizer = SpotifyAuthorizer(configuration: configuration(), store: store,
                                           changed: {})
        let empty = await authorizer.accessToken()
        XCTAssertNil(empty)
        store.save("kein-base64", account: SpotifyConfig.sessionAccount)
        let broken = await authorizer.accessToken()
        XCTAssertNil(broken)
        _ = authorizer.handle(URL(string: "gwenmobile://spotify?code=x")!)
        authorizer.begin()
        authorizer.sessionManager(manager: manager, didInitiate: try XCTUnwrap(
            makeSpotifySession(token: "alt-token", expiresIn: -120)))
        try await settle(400)
        let renewed = await authorizer.accessToken()
        XCTAssertNil(renewed)
    }

    func testTheLiveRemoteWrappers() throws {
        let configuration = SPTConfiguration(clientID: "gap-client",
                                             redirectURL: URL(string: SpotifyConfig.redirectURI)!)
        let remote = LiveSpotifyAppRemote(configuration: configuration)
        _ = remote.isConnected
        remote.accessToken = "token"
        XCTAssertEqual(remote.accessToken, "token")
        _ = remote.player
        _ = remote.delegate
        _ = remote.authorizationToken(from: URL(string: "gwenmobile://spotify?code=x")!)
        remote.subscribeToPlayerState(UnusedPlayerDelegate())
        _ = SPTAppRemotePlayerAPI.self

    }
}

@MainActor
private final class UnusedPlayerDelegate: NSObject, SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {}
}
#endif
