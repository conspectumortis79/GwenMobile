@testable import GwenMobileFeatureCore
import Foundation
#if !targetEnvironment(macCatalyst)
import MediaPlayer
#endif

enum MediaLibrarySystem {
    @MainActor static func install() {
        #if !targetEnvironment(macCatalyst)
        MediaLibraryReader.authorizationStatus = { MPMediaLibrary.authorizationStatus() }
        MediaLibraryReader.requestAuthorization = { await MediaLibraryReader.requestAuthorizationDefault() }
        MediaLibraryIndex.playlists = {
            (MPMediaQuery.playlists().collections ?? []).compactMap { collection in
                guard let playlist = collection as? MPMediaPlaylist else { return nil }
                return RawPlaylist(id: playlist.persistentID, name: playlist.name)
            }
        }
        MediaLibraryIndex.artists = {
            (MPMediaQuery.artists().collections ?? []).compactMap { collection in
                guard let item = collection.representativeItem else { return nil }
                return RawArtist(id: item.artistPersistentID, name: item.artist)
            }
        }
        MediaLibraryIndex.albums = {
            (MPMediaQuery.albums().collections ?? []).compactMap { collection in
                guard let item = collection.representativeItem else { return nil }
                return RawAlbum(id: item.albumPersistentID, title: item.albumTitle, artist: item.artist)
            }
        }
        MediaLibraryIndex.songs = {
            (MPMediaQuery.songs().items ?? []).compactMap { item in
                RawSong(id: item.persistentID, title: item.title, artist: item.artist)
            }
        }
        #endif
    }
}
