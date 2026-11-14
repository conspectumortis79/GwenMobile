@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class SpotifyGapCoverageTests: GwenTestCase {
    private let target = SpotifyTarget(uri: "spotify:track:1",
                                       pick: MusicPick(kind: .song, name: "Tee", artist: "Band"))

    private func source(auth: TestSpotifyAuth, remote: TestSpotifyRemote, web: TestSpotifyWeb,
                        active: Bool) -> SpotifySource {
        SpotifySource(auth: auth, remote: remote, web: web, isActive: { active })
    }

    func testTheSpotifySourceWalksEveryWay() async {
        let auth = TestSpotifyAuth()
        let remote = TestSpotifyRemote(succeeding: true)
        var web = TestSpotifyWeb(target: target, failing: false, result: .done)

        auth.configured = false
        var subject = source(auth: auth, remote: remote, web: web, active: true)
        let notSetUp = await subject.play(MusicRequest(action: .play, query: "Tee"))
        XCTAssertEqual(notSetUp, .notSetUp)

        auth.configured = true
        auth.token = nil
        let notConnected = await subject.play(MusicRequest(action: .play, query: "Tee"))
        XCTAssertEqual(notConnected, .notConnected)

        auth.token = "token"
        subject = source(auth: auth, remote: remote,
                         web: TestSpotifyWeb(target: nil, failing: true, result: .done), active: true)
        let failed = await subject.play(MusicRequest(action: .play, query: "Tee"))
        if case .failed = failed {} else { XCTFail("\(failed)") }

        subject = source(auth: auth, remote: remote,
                         web: TestSpotifyWeb(target: nil, failing: false, result: .done), active: true)
        let notFound = await subject.play(MusicRequest(action: .play, query: "Tee"))
        XCTAssertEqual(notFound, .notFound("Tee"))

        remote.connected = true
        remote.playResult = true
        subject = source(auth: auth, remote: remote, web: web, active: true)
        let played = await subject.play(MusicRequest(action: .play, query: "Tee"))
        XCTAssertEqual(played, .playing(target.pick))

        remote.connected = false
        remote.connectResult = true
        let connectedFirst = await subject.play(MusicRequest(action: .play, query: "Tee"))
        XCTAssertEqual(connectedFirst, .playing(target.pick))

        remote.connected = false
        remote.connectResult = false
        remote.wakeResult = true
        let opened = await subject.play(MusicRequest(action: .play, query: "Tee"))
        XCTAssertEqual(opened, .openedApp(target.pick))
        remote.connected = false
        remote.wakeResult = false
        let missing = await subject.play(MusicRequest(action: .play, query: "Tee"))
        if case .failed = missing {} else { XCTFail("\(missing)") }

        remote.connected = false
        auth.token = "token"
        subject = source(auth: auth, remote: remote, web: web, active: false)
        let webPlayed = await subject.play(MusicRequest(action: .play, query: "Tee"))
        XCTAssertEqual(webPlayed, .playing(target.pick))
        web = TestSpotifyWeb(target: target, failing: false, result: .refused("nein"))
        subject = source(auth: auth, remote: remote, web: web, active: false)
        let refused = await subject.play(MusicRequest(action: .play, query: "Tee"))
        XCTAssertEqual(refused, .failed("nein"))
    }

    func testTheSpotifyControlsWalkEveryWay() async {
        let auth = TestSpotifyAuth()
        let remote = TestSpotifyRemote(succeeding: true)
        let done = TestSpotifyWeb(target: target, failing: false, result: .done)
        var subject = source(auth: auth, remote: remote, web: done, active: true)
        remote.connected = true
        remote.performResult = true
        let paused = await subject.control(.pause)
        XCTAssertEqual(paused, .controlled(.pause))
        remote.performResult = false
        let refused = await subject.control(.next)
        XCTAssertEqual(refused, .failed(L.t("music_spotify_refused")))

        remote.connected = false
        remote.connectResult = true
        remote.performResult = true
        let viaConnect = await subject.control(.previous)
        XCTAssertEqual(viaConnect, .controlled(.previous))
        remote.connected = false
        remote.performResult = false
        let viaWeb = await subject.control(.previous)
        XCTAssertEqual(viaWeb, .controlled(.previous))
        XCTAssertTrue(remote.performed.contains(.previous))

        remote.connected = false
        subject = source(auth: auth, remote: remote,
                         web: TestSpotifyWeb(target: target, failing: false, result: .refused("stopp")),
                         active: false)
        let webRefused = await subject.control(.pause)
        XCTAssertEqual(webRefused, .failed("stopp"))
        let resumed = await subject.control(.resume)
        XCTAssertEqual(resumed, .failed("stopp"))
    }

    func testTheSpotifyWebClientReadsPlaylistsAndTracks() async throws {
        let playlistJSON = #"{"playlists":{"items":[{"name":"Mix","uri":"spotify:playlist:1"}]}}"#
        let searchJSON = #"{"tracks":{"items":[{"name":"Tee","uri":"spotify:track:2","artists":[{"name":"Band"}]}]}}"#
        let client = SpotifyWebClient { request in
            let url = request.url?.absoluteString ?? ""
            return url.contains("/me/playlists") ? (Data(playlistJSON.utf8), 200) : (Data(searchJSON.utf8), 200)
        }
        let own = try await client.find(MusicRequest(action: .play, query: "Mix", kind: .playlist), token: "t")
        XCTAssertEqual(own?.uri, "spotify:playlist:1")
        let track = try await client.find(MusicRequest(action: .play, query: "Tee"), token: "t")
        XCTAssertEqual(track?.uri, "spotify:track:2")
        XCTAssertEqual(track?.pick.artist, "Band")
        let error = SpotifyWebClient { _ in (Data(#"{"error":{"message":"kaputt"}}"#.utf8), 401) }
        do {
            _ = try await error.find(MusicRequest(action: .play, query: "Tee"), token: "t")
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("kaputt"))
        }
        let player = SpotifyWebClient { _ in (Data(), 204) }
        let played = try await player.play(nil, token: "t")
        XCTAssertEqual(played, .done)
        let action = try await player.perform(.next, token: "t")
        XCTAssertEqual(action, .done)
    }

    func testTheSpotifyWebAPIHelpers() throws {
        for kind in MusicKind.allCases {
            XCTAssertFalse(SpotifyWebAPI.searchType(for: kind).isEmpty, "\(kind)")
        }
        let play = try XCTUnwrap(SpotifyWebAPI.play(target, token: "t"))
        XCTAssertEqual(play.httpMethod, "PUT")
        XCTAssertNotNil(play.httpBody)
        let context = try XCTUnwrap(SpotifyWebAPI.play(SpotifyTarget(uri: "spotify:album:1",
                                                                     pick: MusicPick(kind: .album, name: "A")),
                                                       token: "t"))
        XCTAssertEqual(context.httpMethod, "PUT")
        XCTAssertNil(SpotifyWebAPI.control(.play, token: "t")?.httpBody)
        let items = SpotifyWebAPI.targets(from: Data(#"{"tracks":{"items":[{"name":"Tee","uri":"spotify:track:2"}]}}"#.utf8),
                                          kind: .any)
        XCTAssertEqual(items.first?.pick.kind, .song)
        let playlists = SpotifyWebAPI.targets(from: Data(#"{"playlists":{"items":[{"name":"Mix","uri":"spotify:playlist:1"}]}}"#.utf8),
                                              kind: .playlist)
        XCTAssertEqual(SpotifyWebAPI.bestPlaylist("Mix", in: playlists)?.uri, "spotify:playlist:1")
        XCTAssertEqual(SpotifyWebAPI.bestPlaylist("Mix", in: playlists), playlists.first)
        XCTAssertEqual(SpotifyWebAPI.errorMessage(from: Data(#"{"error":{"message":"x"}}"#.utf8)), "x")
        XCTAssertNil(SpotifyWebAPI.errorMessage(from: Data("{}".utf8)))
    }
}
