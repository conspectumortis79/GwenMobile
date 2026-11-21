@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class MusicParsingCoverageTests: GwenTestCase {
    func testTheSearchTypeAndQuery() {
        XCTAssertEqual(SpotifyWebAPI.searchType(for: .artist), "artist")
        XCTAssertEqual(SpotifyWebAPI.searchType(for: .album), "album")
        XCTAssertEqual(SpotifyWebAPI.searchType(for: .playlist), "playlist")
        XCTAssertEqual(SpotifyWebAPI.searchType(for: .song), "track")
        XCTAssertEqual(SpotifyWebAPI.searchType(for: .any), "track")
        XCTAssertEqual(SpotifyWebAPI.searchQuery(for: MusicRequest(action: .play, query: "Hello")), "Hello")
        let withArtist = MusicRequest(action: .play, query: "Hello", artist: "Adele", kind: .song)
        XCTAssertEqual(SpotifyWebAPI.searchQuery(for: withArtist), "Hello artist:Adele")
        let artistKind = MusicRequest(action: .play, query: "Adele", artist: "Adele", kind: .artist)
        XCTAssertEqual(SpotifyWebAPI.searchQuery(for: artistKind), "Adele")
    }

    func testTheRequestsCarryTheRightQuery() throws {
        let search = try XCTUnwrap(SpotifyWebAPI.search(MusicRequest(action: .play, query: "Hello"),
                                                        token: "t"))
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(search.url),
                                                     resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/v1/search")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["q"], "Hello")
        XCTAssertEqual(items["type"], "track")
        XCTAssertEqual(items["limit"], "10")
        XCTAssertEqual(search.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertEqual(search.timeoutInterval, SpotifyWebAPI.timeout)
        XCTAssertEqual(try XCTUnwrap(SpotifyWebAPI.myPlaylists(token: "t")).url?.path, "/v1/me/playlists")
    }

    func testThePlayRequestsCarryTheTarget() throws {
        let track = SpotifyTarget(uri: "spotify:track:1", pick: MusicPick(kind: .song, name: "A"))
        let playTrack = try XCTUnwrap(SpotifyWebAPI.play(track, token: "t"))
        XCTAssertEqual(playTrack.httpMethod, "PUT")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(playTrack.httpBody)) as? [String: Any]
        XCTAssertEqual(body?["uris"] as? [String], ["spotify:track:1"])
        let context = SpotifyTarget(uri: "spotify:album:1", pick: MusicPick(kind: .album, name: "B"))
        let playContext = try XCTUnwrap(SpotifyWebAPI.play(context, token: "t"))
        let contextBody = try JSONSerialization.jsonObject(with: try XCTUnwrap(playContext.httpBody))
            as? [String: Any]
        XCTAssertEqual(contextBody?["context_uri"] as? String, "spotify:album:1")
        XCTAssertNil(try XCTUnwrap(SpotifyWebAPI.play(nil, token: "t")).httpBody)
    }

    func testTheControlPaths() throws {
        XCTAssertEqual(try XCTUnwrap(SpotifyWebAPI.control(.pause, token: "t")).httpMethod, "PUT")
        XCTAssertEqual(try XCTUnwrap(SpotifyWebAPI.control(.next, token: "t")).httpMethod, "POST")
        XCTAssertEqual(try XCTUnwrap(SpotifyWebAPI.control(.previous, token: "t")).url?.path,
                       "/v1/me/player/previous")
        XCTAssertEqual(try XCTUnwrap(SpotifyWebAPI.control(.play, token: "t")).url?.path, "/v1/me/player/play")
        XCTAssertEqual(try XCTUnwrap(SpotifyWebAPI.control(.resume, token: "t")).url?.path, "/v1/me/player/play")
    }

    func testTheTargetParsing() {
        let json = #"{"tracks":{"items":[{"uri":"spotify:track:1","name":"Hello","artists":[{"name":"Adele"}]},{"name":"ohne uri"}]}}"#
        let targets = SpotifyWebAPI.targets(from: Data(json.utf8), kind: .song)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.pick.artist, "Adele")
        let fallback = #"{"items":[{"uri":"spotify:track:2","name":"Fallback"}]}"#
        XCTAssertEqual(SpotifyWebAPI.targets(from: Data(fallback.utf8), kind: .any).first?.pick.kind, .song)
        XCTAssertTrue(SpotifyWebAPI.targets(from: Data("{}".utf8), kind: .song).isEmpty)
        XCTAssertTrue(SpotifyWebAPI.targets(from: Data("kaputt".utf8), kind: .song).isEmpty)
    }

    func testTheErrorMessageAndBestPlaylist() {
        XCTAssertEqual(SpotifyWebAPI.errorMessage(from: Data(#"{"error":{"message":"kaputt"}}"#.utf8)), "kaputt")
        XCTAssertNil(SpotifyWebAPI.errorMessage(from: Data("{}".utf8)))
        let exact = SpotifyTarget(uri: "u1", pick: MusicPick(kind: .playlist, name: "Sport Mix"))
        let close = SpotifyTarget(uri: "u2", pick: MusicPick(kind: .playlist, name: "Sport Mix Neu"))
        XCTAssertEqual(SpotifyWebAPI.bestPlaylist("Sport Mix", in: [close, exact])?.uri, "u1")
        XCTAssertEqual(SpotifyWebAPI.bestPlaylist("Sport Mix", in: [close])?.uri, "u2")
        XCTAssertNil(SpotifyWebAPI.bestPlaylist("", in: [exact]))
        XCTAssertNil(SpotifyWebAPI.bestPlaylist("Nichts", in: []))
    }

    func testTheITunesCatalogHelpers() throws {
        XCTAssertEqual(ITunesCatalog.country(Locale(identifier: "de_DE")), "de")
        let search = try XCTUnwrap(ITunesCatalog.searchURL(term: "Adele", entity: "song", limit: 5,
                                                           country: "de"))
        XCTAssertTrue(search.absoluteString.contains("term=Adele"))
        let attributed = try XCTUnwrap(ITunesCatalog.searchURL(term: "Adele", entity: "album",
                                                               attribute: "artistTerm", limit: 5,
                                                               country: "de"))
        XCTAssertTrue(attributed.absoluteString.contains("attribute=artistTerm"))
        let lookup = try XCTUnwrap(ITunesCatalog.lookupURL(collectionID: 42, country: "de"))
        XCTAssertTrue(lookup.absoluteString.contains("id=42"))
        let json = #"{"results":[{"wrapperType":"track","trackId":1,"trackName":"Hello","artistName":"Adele","trackNumber":1},{"wrapperType":"collection","collectionId":2,"collectionName":"Album"},{"wrapperType":"other","trackName":"x"}]}"#
        let items = ITunesCatalog.items(from: Data(json.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(ITunesCatalog.artistFits(items[0], "Adele"))
        XCTAssertTrue(ITunesCatalog.artistFits(items[0], ""))
        XCTAssertFalse(ITunesCatalog.artistFits(items[0], "Beatles"))
        XCTAssertTrue(ITunesCatalog.items(from: Data("{}".utf8)).isEmpty)
    }

    func testTheITunesSearchBuildsPicks() async throws {
        let track = #"{"results":[{"wrapperType":"track","trackId":1,"trackName":"Hello","artistName":"Adele"}]}"#
        let search = ITunesCatalogSearch(country: "de") { _ in Data(track.utf8) }
        let pick = try await search.find(MusicRequest(action: .play, query: "Hello", artist: "Adele",
                                                      kind: .song))
        XCTAssertEqual(pick?.pick.name, "Hello")
        let album = #"{"results":[{"wrapperType":"collection","collectionId":2,"collectionName":"Album","artistName":"Adele"}]}"#
        let albumSearch = ITunesCatalogSearch(country: "de") { url in
            url.absoluteString.contains("/lookup") ? Data(track.utf8) : Data(album.utf8)
        }
        let albumPick = try await albumSearch.find(MusicRequest(action: .play, query: "Album",
                                                                artist: "Adele", kind: .album))
        XCTAssertEqual(albumPick?.pick.kind, .album)
        let empty = ITunesCatalogSearch(country: "de") { _ in Data("{}".utf8) }
        let emptySong = try await empty.find(MusicRequest(action: .play, query: "x", kind: .song))
        XCTAssertNil(emptySong)
        let emptyPlaylist = try await empty.find(MusicRequest(action: .play, query: "x", kind: .playlist))
        XCTAssertNil(emptyPlaylist)
    }
}
