import GwenMobileKit
import Foundation
import UIKit
#if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
import SpotifyiOS
#endif

@MainActor
final class SpotifyLink: ObservableObject {
    static let shared = SpotifyLink()

    @Published private(set) var signedIn = false

    private let clientID: @MainActor () -> String
    private let keychain: any KeyStoring
    #if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
    private var parts: (client: String, auth: SpotifyAuthorizer, remote: SpotifyRemote)?
    #endif

    init(clientID: @escaping @MainActor () -> String = { AppSettings.shared.music.spotifyClientID },
         keychain: any KeyStoring = KeychainKeyStore()) {
        self.clientID = clientID
        self.keychain = keychain
        signedIn = !keychain.read(account: SpotifyConfig.sessionAccount).text.isEmpty
    }

    static var isAvailable: Bool {
        #if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    var isConfigured: Bool { !SpotifyConfig.cleaned(clientID()).isEmpty }

    func signIn() {
        #if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
        current()?.auth.begin()
        #endif
    }

    func signOut() {
        keychain.delete(account: SpotifyConfig.sessionAccount)
        refresh()
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard SpotifyConfig.isCallback(url) else { return false }
        #if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
        guard let parts = current() else { return false }
        if parts.remote.handle(url) { return true }
        return parts.auth.handle(url)
        #else
        return false
        #endif
    }

    private func refresh() {
        signedIn = !keychain.read(account: SpotifyConfig.sessionAccount).text.isEmpty
    }

    #if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
    private func current() -> (client: String, auth: SpotifyAuthorizer, remote: SpotifyRemote)? {
        let client = SpotifyConfig.cleaned(clientID())
        guard !client.isEmpty, let redirect = URL(string: SpotifyConfig.redirectURI) else { return nil }
        if let parts, parts.client == client { return parts }
        parts?.remote.shutdown()
        let configuration = SPTConfiguration(clientID: client, redirectURL: redirect)
        configuration.playURI = ""
        let made = (client: client,
                    auth: SpotifyAuthorizer(configuration: configuration, store: keychain,
                                            changed: { [weak self] in self?.refresh() }),
                    remote: SpotifyRemote(configuration: configuration))
        parts = made
        return made
    }
    #endif
}

#if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
extension SpotifyLink: SpotifyAuthorizing, SpotifyRemoteControlling {
    func accessToken() async -> String? { await current()?.auth.accessToken() }

    var isConnected: Bool { parts?.remote.isConnected ?? false }

    var isPlaying: Bool { parts?.remote.isPlaying ?? false }

    func connect(token: String) async -> Bool { await current()?.remote.connect(token: token) ?? false }

    func play(uri: String) async -> Bool { await current()?.remote.play(uri: uri) ?? false }

    func perform(_ action: MusicAction) async -> Bool { await current()?.remote.perform(action) ?? false }

    func wakeAndPlay(uri: String) async -> Bool { await current()?.remote.wakeAndPlay(uri: uri) ?? false }
}

enum SpotifySourceFactory {
    @MainActor static func make() -> (any MusicSource)? {
        SpotifySource(auth: SpotifyLink.shared, remote: SpotifyLink.shared, web: SpotifyWebClient(),
                      isActive: { UIApplication.shared.applicationState == .active })
    }
}
#else
enum SpotifySourceFactory {
    @MainActor static func make() -> (any MusicSource)? { nil }
}
#endif
