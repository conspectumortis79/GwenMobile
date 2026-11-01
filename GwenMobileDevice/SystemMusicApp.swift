@testable import GwenMobileFeatureCore
import GwenMobileKit
#if !targetEnvironment(macCatalyst)
import Foundation
import MediaPlayer

@MainActor
final class SystemMusicApp: MusicAppPlaying {
    static let prepareSeconds: Double = 8

    private var player: MPMusicPlayerController { .systemMusicPlayer }

    var isPlaying: Bool { player.playbackState == .playing }

    func play(_ entry: MusicLibraryEntry) async -> Bool {
        if entry.kind == .playlist {
            let query = MPMediaQuery.playlists()
            query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: entry.id),
                                                              forProperty: MPMediaPlaylistPropertyPersistentID))
            guard let playlist = query.collections?.first else { return false }
            player.setQueue(with: playlist)
        } else {
            let query = MPMediaQuery.songs()
            query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: entry.id),
                                                              forProperty: Self.property(of: entry.kind)))
            player.setQueue(with: query)
        }
        return await start()
    }

    func play(storeIDs: [String]) async -> Bool {
        player.setQueue(with: storeIDs)
        return await start()
    }

    func perform(_ action: MusicAction) {
        switch action {
        case .pause: player.pause()
        case .next: player.skipToNextItem()
        case .previous: player.skipToPreviousItem()
        case .play, .resume: player.play()
        }
    }

    static func property(of kind: MusicKind) -> String {
        switch kind {
        case .artist: return MPMediaItemPropertyArtistPersistentID
        case .album: return MPMediaItemPropertyAlbumPersistentID
        case .song, .playlist, .any: return MPMediaItemPropertyPersistentID
        }
    }

    private func start() async -> Bool {
        let problem = await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
            let resumed = LockedValue(false)
            let finish: @Sendable (String?) -> Void = { value in
                if !resumed.exchange(true) { done.resume(returning: value) }
            }
            player.prepareToPlay { error in finish(error.map { "\($0)" }) }
            Task {
                try? await Task.sleep(for: .seconds(Self.prepareSeconds))
                finish("zeitlimit")
            }
        }
        if let problem {
            flowMark("MUSIK apple vorbereitung fehler=" + TextLine.oneLine(problem, limit: 160))
            return false
        }
        player.play()
        return true
    }
}
#endif

enum MusicSystem {
    @MainActor static func install() {
        #if !targetEnvironment(macCatalyst)
        MusicAppPort.current = SystemMusicApp()
        #endif
    }
}
