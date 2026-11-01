import GwenMobileKit
import Foundation

enum SpotifyConfig {
    static let redirectURI = "gwenmobile://spotify-login-callback"
    static let callbackHost = "spotify-login-callback"
    static let sessionAccount = "spotify.session"
    static let bundleID = "com.mortis.gwenmobile"
    static let connectSeconds: Double = 4
    static let renewSeconds: Double = 15
    static let commandSeconds: Double = 10

    static func isCallback(_ url: URL) -> Bool {
        url.scheme == "gwenmobile" && url.host == callbackHost
    }

    static func cleaned(_ clientID: String) -> String {
        clientID.trimmed
    }
}
