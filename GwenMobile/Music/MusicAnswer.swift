import GwenMobileKit

enum MusicAnswer {
    static func text(_ outcome: MusicOutcome, service: MusicService) -> String {
        let label = service.label
        switch outcome {
        case .playing(let pick): return L.fmt2(playingKey(pick.kind), described(pick), label)
        case .resumed: return L.fmt("music_resumed", label)
        case .controlled(let action): return L.fmt(controlKey(action), label)
        case .openedApp(let pick):
            return pick.map { L.fmt("music_opened_app_with", described($0)) } ?? L.t("music_opened_app")
        case .notFound(let asked): return L.fmt2("music_not_found", asked, label)
        case .catalogRefused(let name): return L.fmt("music_catalog_refused", name)
        case .libraryDenied: return L.t("music_library_denied")
        case .notSetUp: return L.t("music_spotify_not_set_up")
        case .notConnected: return L.t("music_spotify_not_connected")
        case .unsupported: return L.fmt("music_unsupported", label)
        case .failed(let detail): return L.fmt2("music_failed", label, detail)
        }
    }

    static func described(_ pick: MusicPick) -> String {
        guard let artist = pick.artist, !artist.isEmpty, pick.kind != .artist, pick.kind != .playlist else {
            return pick.name
        }
        return "\(pick.name) – \(artist)"
    }

    static func playingKey(_ kind: MusicKind) -> String {
        switch kind {
        case .playlist: return "music_playing_playlist"
        case .artist: return "music_playing_artist"
        case .song, .album, .any: return "music_playing"
        }
    }

    static func controlKey(_ action: MusicAction) -> String {
        switch action {
        case .pause: return "music_paused"
        case .next: return "music_next"
        case .previous: return "music_previous"
        case .play, .resume: return "music_resumed"
        }
    }
}
