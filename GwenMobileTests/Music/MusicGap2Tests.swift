@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import MediaPlayer
import XCTest
import GwenMobileKit

@MainActor
final class MusicGap2Tests: GwenTestCase {
    func testTheITunesDownloadAndSpotifyTransport() async {
        MockHTTP.install { _ in (200, Data("{}".utf8)) }
        defer { MockHTTP.uninstall() }
        _ = try? await ITunesCatalogSearch.download(URL(string: "https://itunes.apple.com/lookup")!)
        let request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        let (data, status) = (try? await SpotifyWebClient.transport(request)) ?? (Data(), -1)
        XCTAssertEqual(status, 200)
        XCTAssertFalse(data.isEmpty)
    }

    #if !targetEnvironment(macCatalyst)
    func testTheSystemMusicAppActions() async {
        let app = SystemMusicApp()
        _ = app.isPlaying
        _ = await app.play(storeIDs: [])
        app.perform(.play)
        app.perform(.resume)
        app.perform(.pause)
        app.perform(.next)
        app.perform(.previous)
        let playlist = MusicLibraryEntry(kind: .playlist, id: 42, name: "Liste")
        _ = await app.play(playlist)
        let song = MusicLibraryEntry(kind: .song, id: 43, name: "Lied")
        _ = await app.play(song)
        XCTAssertEqual(SystemMusicApp.property(of: .artist), MPMediaItemPropertyArtistPersistentID)
        XCTAssertEqual(SystemMusicApp.property(of: .album), MPMediaItemPropertyAlbumPersistentID)
        XCTAssertEqual(SystemMusicApp.property(of: .song), MPMediaItemPropertyPersistentID)
    }

    func testSmokeTheSpotifyLinkEntryPoints() async {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        _ = await SpotifyLink.shared.wakeAndPlay(uri: "spotify:track:1")
        _ = SpotifyLink.shared.handle(URL(string: "https://example.test/ohne")!)
        SpotifyLink.shared.signOut()
        SpotifyLink.shared.signIn()
        _ = SpotifyLink.shared.signedIn
    }
    #endif
}
