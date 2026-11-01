import GwenMobileKit
#if canImport(SpotifyiOS) && !targetEnvironment(macCatalyst)
import Foundation
import SpotifyiOS
import UIKit

@MainActor
final class SpotifyRemote: NSObject, SpotifyRemoteControlling, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    private let appRemote: any SpotifyAppRemoteDriving
    private var connecting: [CheckedContinuation<Bool, Never>] = []
    private var attempt = 0
    private var wantsConnection = false
    private var observers: [NSObjectProtocol] = []
    private(set) var isPlaying = false

    convenience init(configuration: SPTConfiguration) {
        self.init(appRemote: LiveSpotifyAppRemote(configuration: configuration))
    }

    init(appRemote: any SpotifyAppRemoteDriving) {
        self.appRemote = appRemote
        super.init()
        appRemote.delegate = self
        followLifecycle()
    }

    var isConnected: Bool { appRemote.isConnected }

    func connect(token: String) async -> Bool {
        if appRemote.isConnected { return true }
        appRemote.accessToken = token
        wantsConnection = true
        return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            connecting.append(done)
            guard connecting.count == 1 else { return }
            attempt += 1
            let mine = attempt
            appRemote.connect()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(SpotifyConfig.connectSeconds))
                if self.attempt == mine { self.finishConnecting(false) }
            }
        }
    }

    func play(uri: String) async -> Bool {
        guard let player = appRemote.player else { return false }
        return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let finish = Self.answer(done)
            player.play(uri) { ok in finish(ok) }
            Self.timeLimit { finish(false) }
        }
    }

    func perform(_ action: MusicAction) async -> Bool {
        guard let player = appRemote.player else { return false }
        return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let finish = Self.answer(done)
            let reply: @Sendable (Bool) -> Void = { finish($0) }
            switch action {
            case .pause: player.pause(reply)
            case .next: player.skipToNext(reply)
            case .previous: player.skipToPrevious(reply)
            case .play, .resume: player.resume(reply)
            }
            Self.timeLimit { finish(false) }
        }
    }

    func wakeAndPlay(uri: String) async -> Bool {
        wantsConnection = true
        return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let finish = Self.answer(done)
            appRemote.authorizeAndPlay(uri: uri) { opened in finish(opened) }
            Self.timeLimit { finish(false) }
        }
    }

    private static func answer(_ done: CheckedContinuation<Bool, Never>) -> @Sendable (Bool) -> Void {
        let resumed = LockedValue(false)
        return { value in
            if !resumed.exchange(true) { done.resume(returning: value) }
        }
    }

    private static func timeLimit(_ finish: @escaping @Sendable () -> Void) {
        Task {
            try? await Task.sleep(for: .seconds(SpotifyConfig.commandSeconds))
            finish()
        }
    }

    func handle(_ url: URL) -> Bool {
        guard let token = appRemote.authorizationToken(from: url) else { return false }
        appRemote.accessToken = token
        appRemote.connect()
        return true
    }

    private func finishConnecting(_ connected: Bool) {
        attempt += 1
        let pending = connecting
        connecting = []
        pending.forEach { $0.resume(returning: connected) }
    }

    func shutdown() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        pauseConnection()
    }

    private func followLifecycle() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pauseConnection() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeConnection() }
        })
    }

    private func pauseConnection() {
        guard appRemote.isConnected else { return }
        appRemote.disconnect()
    }

    private func resumeConnection() {
        guard wantsConnection, !appRemote.isConnected, appRemote.accessToken != nil else { return }
        appRemote.connect()
    }

    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            flowMark("SPOTIFY fernsteuerung verbunden")
            self.appRemote.subscribeToPlayerState(self)
            self.finishConnecting(true)
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let detail = TextLine.oneLine(error?.localizedDescription ?? "-", limit: 160)
        Task { @MainActor in
            flowMark("SPOTIFY fernsteuerung fehlgeschlagen \(detail)")
            self.finishConnecting(false)
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        Task { @MainActor in
            self.isPlaying = false
            flowMark("SPOTIFY fernsteuerung getrennt")
        }
    }

    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let paused = playerState.isPaused
        Task { @MainActor in self.isPlaying = !paused }
    }
}

@MainActor
protocol SpotifyAppRemoteDriving: AnyObject {
    var isConnected: Bool { get }
    var accessToken: String? { get set }
    var player: (any SpotifyPlayerDriving)? { get }
    var delegate: SPTAppRemoteDelegate? { get set }

    func connect()
    func disconnect()
    func authorizeAndPlay(uri: String, completion: @escaping @Sendable (Bool) -> Void)
    func authorizationToken(from url: URL) -> String?
    func subscribeToPlayerState(_ delegate: SPTAppRemotePlayerStateDelegate)
}

@MainActor
protocol SpotifyPlayerDriving: AnyObject {
    func play(_ uri: String, reply: @escaping @Sendable (Bool) -> Void)
    func pause(_ reply: @escaping @Sendable (Bool) -> Void)
    func skipToNext(_ reply: @escaping @Sendable (Bool) -> Void)
    func skipToPrevious(_ reply: @escaping @Sendable (Bool) -> Void)
    func resume(_ reply: @escaping @Sendable (Bool) -> Void)
}

@MainActor
final class LiveSpotifyAppRemote: SpotifyAppRemoteDriving {
    private let appRemote: SPTAppRemote

    init(configuration: SPTConfiguration) {
        appRemote = SPTAppRemote(configuration: configuration, logLevel: .error)
    }

    var isConnected: Bool { appRemote.isConnected }

    var accessToken: String? {
        get { appRemote.connectionParameters.accessToken }
        set { appRemote.connectionParameters.accessToken = newValue }
    }

    var player: (any SpotifyPlayerDriving)? {
        appRemote.playerAPI.map(LiveSpotifyPlayer.init)
    }

    var delegate: SPTAppRemoteDelegate? {
        get { appRemote.delegate }
        set { appRemote.delegate = newValue }
    }

    func connect() { appRemote.connect() }
    func disconnect() { appRemote.disconnect() }

    func authorizeAndPlay(uri: String, completion: @escaping @Sendable (Bool) -> Void) {
        appRemote.authorizeAndPlayURI(uri) { opened in completion(opened) }
    }

    func authorizationToken(from url: URL) -> String? {
        appRemote.authorizationParameters(from: url)?[SPTAppRemoteAccessTokenKey]
    }

    func subscribeToPlayerState(_ delegate: SPTAppRemotePlayerStateDelegate) {
        appRemote.playerAPI?.delegate = delegate
        appRemote.playerAPI?.subscribe(toPlayerState: nil)
    }
}

@MainActor
final class LiveSpotifyPlayer: SpotifyPlayerDriving {
    private let player: SPTAppRemotePlayerAPI

    init(_ player: SPTAppRemotePlayerAPI) {
        self.player = player
    }

    func play(_ uri: String, reply: @escaping @Sendable (Bool) -> Void) {
        player.play(uri) { _, error in reply(error == nil) }
    }

    func pause(_ reply: @escaping @Sendable (Bool) -> Void) {
        player.pause { _, error in reply(error == nil) }
    }

    func skipToNext(_ reply: @escaping @Sendable (Bool) -> Void) {
        player.skip(toNext: { _, error in reply(error == nil) })
    }

    func skipToPrevious(_ reply: @escaping @Sendable (Bool) -> Void) {
        player.skip(toPrevious: { _, error in reply(error == nil) })
    }

    func resume(_ reply: @escaping @Sendable (Bool) -> Void) {
        player.resume { _, error in reply(error == nil) }
    }
}
#endif
