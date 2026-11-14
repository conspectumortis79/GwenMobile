@testable import GwenMobileFeatureCore
#if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
import ObjectiveC
import SpotifyiOS
import XCTest
import GwenMobileKit

@MainActor
final class SpotifyRuntimeProbeTests: GwenTestCase {
    func testTheSessionRuntimeInit() throws {
        let selector = NSSelectorFromString("initWithAccessToken:refreshToken:expirationDate:scope:")
        guard let method = class_getInstanceMethod(SPTSession.self, selector) else {
            XCTFail("kein Initialisierer")
            return
        }
        let instance = class_createInstance(SPTSession.self, 0) as AnyObject
        typealias InitIMP = @convention(c) (AnyObject, Selector, NSString, NSString, NSDate, UInt) -> AnyObject?
        let function = unsafeBitCast(method_getImplementation(method), to: InitIMP.self)
        let raw = function(instance, selector, "token" as NSString, "refresh" as NSString,
                           Date().addingTimeInterval(3600) as NSDate, 0)
        let session = try XCTUnwrap(raw as? SPTSession)
        XCTAssertEqual(session.accessToken, "token")
        XCTAssertFalse(session.isExpired)
        let fresh = class_createInstance(SPTSession.self, 0) as AnyObject
        let expired = try XCTUnwrap(function(fresh, selector,
                                             "alt" as NSString, "refresh" as NSString,
                                             Date().addingTimeInterval(-60) as NSDate, 0) as? SPTSession)
        XCTAssertTrue(expired.isExpired)
    }

    func testTheLiveRemoteWrappers() throws {
        let configuration = SPTConfiguration(clientID: "probe-client",
                                             redirectURL: URL(string: SpotifyConfig.redirectURI)!)
        let remote = LiveSpotifyAppRemote(configuration: configuration)
        _ = remote.isConnected
        remote.accessToken = "token"
        XCTAssertEqual(remote.accessToken, "token")
        _ = remote.player
        _ = remote.delegate
        _ = remote.authorizationToken(from: URL(string: "gwenmobile://spotify?code=x")!)
        if let player = remote.player {
            _ = player
        }
    }
}
#endif
