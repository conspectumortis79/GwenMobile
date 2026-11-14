@testable import GwenMobileFeatureCore
#if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
import Foundation
import SpotifyiOS
import XCTest
import GwenMobileKit

@MainActor
final class SpotifyAuthorizerCoverageTests: GwenTestCase {
    private func configuration() -> SPTConfiguration {
        SPTConfiguration(clientID: "test-client", redirectURL: URL(string: SpotifyConfig.redirectURI)!)
    }

    func testTheAuthorizerHandlesURLsAndFailures() async {
        let store = MemoryKeyStore()
        var changes = 0
        let authorizer = SpotifyAuthorizer(configuration: configuration(), store: store,
                                           changed: { changes += 1 })
        XCTAssertFalse(authorizer.handle(URL(string: "https://example.test/other")!))
        let token = await authorizer.accessToken()
        XCTAssertNil(token)
        authorizer.sessionManager(manager: SPTSessionManager(configuration: configuration(), delegate: nil),
                                  didFailWith: APIError(message: "kaputt"))
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(changes, 0)
        _ = SpotifyAuthorizer.scope
        XCTAssertTrue(store.read(account: SpotifyConfig.sessionAccount).text.isEmpty)
    }

}
#endif
