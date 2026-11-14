import GwenMobileKit
#if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
import Foundation
import SpotifyiOS
import UIKit

@MainActor
final class SpotifyAuthorizer: NSObject, SPTSessionManagerDelegate {
    static let scope: SPTScope = [.appRemoteControl, .playlistReadPrivate, .playlistReadCollaborative,
                                  .userModifyPlaybackState, .userReadPlaybackState]

    private let manager: SPTSessionManager
    private let keychain: any KeyStoring
    private var waiting: [CheckedContinuation<String?, Never>] = []
    private var renewal = 0
    private let changed: @MainActor () -> Void

    init(configuration: SPTConfiguration, store: any KeyStoring, changed: @escaping @MainActor () -> Void) {
        keychain = store
        self.changed = changed
        manager = SPTSessionManager(configuration: configuration, delegate: nil)
        super.init()
        manager.delegate = self
    }

    func begin() {
        manager.initiateSession(with: Self.scope, options: .default, campaign: nil)
    }

    func handle(_ url: URL) -> Bool {
        manager.application(UIApplication.shared, open: url, options: [:])
    }

    func accessToken() async -> String? {
        guard let session = stored() else { return nil }
        if !session.isExpired { return session.accessToken }
        return await renewed(session)
    }

    private func renewed(_ session: SPTSession) async -> String? {
        await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
            waiting.append(done)
            guard waiting.count == 1 else { return }
            renewal += 1
            let mine = renewal
            manager.session = session
            manager.renewSession()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(SpotifyConfig.renewSeconds))
                if self.renewal == mine { self.finish(nil) }
            }
        }
    }

    private func finish(_ token: String?) {
        let pending = waiting
        waiting = []
        pending.forEach { $0.resume(returning: token) }
    }

    private func keep(_ archived: Data, token: String) {
        keychain.save(archived.base64EncodedString(), account: SpotifyConfig.sessionAccount)
        changed()
        finish(token)
    }

    private func stored() -> SPTSession? {
        guard let data = Data(base64Encoded: keychain.read(account: SpotifyConfig.sessionAccount).text) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: SPTSession.self, from: data)
    }

    nonisolated static func archive(_ session: SPTSession) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: session, requiringSecureCoding: true)
    }

    nonisolated func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        persist(session, label: "angemeldet")
    }

    nonisolated func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        persist(session, label: "erneuert")
    }

    nonisolated func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        let detail = TextLine.oneLine(error.localizedDescription, limit: 160)
        Task { @MainActor in
            flowMark("SPOTIFY anmeldung fehler=\(detail)")
            self.finish(nil)
        }
    }

    nonisolated private func persist(_ session: SPTSession, label: String) {
        let token = session.accessToken
        guard let archived = Self.archive(session) else { return }
        Task { @MainActor in
            flowMark("SPOTIFY sitzung \(label)")
            self.keep(archived, token: token)
        }
    }
}
#endif
