import GwenMobileKit
#if !targetEnvironment(macCatalyst)
import Foundation
import MediaPlayer

protocol MusicLibraryReading: Sendable {
    func access() async -> Bool
    func entries(of kinds: [MusicKind]) async -> [MusicLibraryEntry]
}

struct MediaLibraryReader: MusicLibraryReading {
    nonisolated(unsafe) static var authorizationStatus: @Sendable () -> MPMediaLibraryAuthorizationStatus = {
        .denied
    }

    nonisolated(unsafe) static var requestAuthorization: @Sendable () async -> MPMediaLibraryAuthorizationStatus = {
        .denied
    }

    nonisolated static func requestAuthorizationDefault() async -> MPMediaLibraryAuthorizationStatus {
        await withCheckedContinuation { (done: CheckedContinuation<MPMediaLibraryAuthorizationStatus, Never>) in
            MPMediaLibrary.requestAuthorization { done.resume(returning: $0) }
        }
    }

    func access() async -> Bool {
        switch Self.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            let status = await Self.requestAuthorization()
            return status == .authorized
        default: return false
        }
    }

    func entries(of kinds: [MusicKind]) async -> [MusicLibraryEntry] {
        await Offload.orNil { kinds.flatMap(MediaLibraryIndex.entries(of:)) } ?? []
    }
}

struct RawPlaylist: Sendable {
    var id: UInt64
    var name: String?
}

struct RawArtist: Sendable {
    var id: UInt64
    var name: String?
}

struct RawAlbum: Sendable {
    var id: UInt64
    var title: String?
    var artist: String?
}

struct RawSong: Sendable {
    var id: UInt64
    var title: String?
    var artist: String?
}

enum MediaLibraryIndex {
    nonisolated(unsafe) static var playlists: @Sendable () -> [RawPlaylist] = { [] }
    nonisolated(unsafe) static var artists: @Sendable () -> [RawArtist] = { [] }
    nonisolated(unsafe) static var albums: @Sendable () -> [RawAlbum] = { [] }
    nonisolated(unsafe) static var songs: @Sendable () -> [RawSong] = { [] }

    static func entries(of kind: MusicKind) -> [MusicLibraryEntry] {
        switch kind {
        case .playlist:
            return playlists().compactMap { raw in
                guard let name = raw.name else { return nil }
                return MusicLibraryEntry(kind: .playlist, id: raw.id, name: name)
            }
        case .artist:
            return artists().compactMap { raw in
                guard let name = raw.name else { return nil }
                return MusicLibraryEntry(kind: .artist, id: raw.id, name: name)
            }
        case .album:
            return albums().compactMap { raw in
                guard let title = raw.title else { return nil }
                return MusicLibraryEntry(kind: .album, id: raw.id, name: title, artist: raw.artist)
            }
        case .song:
            return songs().compactMap { raw in
                guard let title = raw.title else { return nil }
                return MusicLibraryEntry(kind: .song, id: raw.id, name: title, artist: raw.artist)
            }
        case .any:
            return []
        }
    }
}
#endif
