@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

private final class GapKeyStore: KeyStoring, @unchecked Sendable {
    var values: [String: String] = [:]

    func read(account: String) -> KeychainRead {
        values[account].map(KeychainRead.value) ?? .absent
    }

    @discardableResult
    func save(_ value: String, account: String) -> Bool {
        values[account] = value
        return true
    }

    @discardableResult
    func delete(account: String) -> Bool {
        values[account] = nil
        return true
    }
}

@MainActor
final class MusicGapCoverageTests: GwenTestCase {
    func testTheMusicAnswersCoverEveryOutcome() {
        for kind in MusicKind.allCases {
            let text = MusicAnswer.text(.playing(MusicPick(kind: kind, name: "Lied", artist: "Band")),
                                        service: .spotify)
            XCTAssertFalse(text.isEmpty, "\(kind)")
        }
        let outcomes: [MusicOutcome] = [.resumed,
                                        .controlled(.pause), .controlled(.next), .controlled(.previous),
                                        .controlled(.play), .controlled(.resume),
                                        .openedApp(nil),
                                        .openedApp(MusicPick(kind: .song, name: "X")),
                                        .notFound("x"), .catalogRefused("y"), .libraryDenied, .notSetUp,
                                        .notConnected, .unsupported, .failed("kaputt")]
        for outcome in outcomes {
            XCTAssertFalse(MusicAnswer.text(outcome, service: .appleMusic).isEmpty, "\(outcome)")
        }
        for action in [MusicAction.pause, .next, .previous, .play, .resume] {
            XCTAssertFalse(MusicAnswer.controlKey(action).isEmpty, "\(action)")
        }
        XCTAssertTrue(MusicAnswer.text(.resumed, service: .spotify).contains(MusicService.spotify.label))
        XCTAssertTrue(MusicAnswer.text(.failed("kaputt"), service: .spotify).contains("kaputt"))
        XCTAssertTrue(MusicOutcome.playing(MusicPick(kind: .song, name: "X")).soundsNow)
        XCTAssertFalse(MusicOutcome.notFound("X").soundsNow)
    }

    func testTheLibraryMatchingRespectsArtistAndKind() {
        let entries = [
            MusicLibraryEntry(kind: .song, id: 1, name: "Mein Lied", artist: "Band A"),
            MusicLibraryEntry(kind: .song, id: 2, name: "Mein Lied", artist: "Band B"),
            MusicLibraryEntry(kind: .album, id: 3, name: "Mein Album", artist: "Band A"),
            MusicLibraryEntry(kind: .playlist, id: 4, name: "Meine Liste"),
        ]
        let byArtist = MusicRequest(action: .play, query: "Mein Lied", artist: "Band B")
        XCTAssertEqual(MusicLibraryMatching.best(for: byArtist, in: entries)?.id, 2)
        let byKind = MusicRequest(action: .play, query: "Mein Album", kind: .album)
        XCTAssertEqual(MusicLibraryMatching.best(for: byKind, in: entries)?.id, 3)
        let close = MusicRequest(action: .play, query: "Lied")
        XCTAssertEqual(MusicLibraryMatching.best(for: close, in: entries)?.id, 1)
        let playlist = MusicRequest(action: .play, query: "Meine Liste")
        XCTAssertEqual(MusicLibraryMatching.best(for: playlist, in: entries)?.id, 4)
        let empty = MusicRequest(action: .play, query: "")
        XCTAssertNil(MusicLibraryMatching.best(for: empty, in: entries))
    }

    func testTheCatalogURLsAndParsing() throws {
        XCTAssertEqual(ITunesCatalog.country(Locale(identifier: "de_DE")), "de")
        let url = try XCTUnwrap(ITunesCatalog.searchURL(term: "Tee", entity: "song", limit: 5, country: "de"))
        XCTAssertTrue(url.absoluteString.contains("country=de"))
        XCTAssertTrue(url.absoluteString.contains("entity=song"))
        XCTAssertNotNil(ITunesCatalog.lookupURL(collectionID: 42, country: "de"))
        let json = #"""
        {"results":[
          {"wrapperType":"track","trackId":7,"trackName":"Tee","artistName":"Band","collectionId":9,"trackNumber":1},
          {"wrapperType":"collection","collectionName":"Album","collectionId":9,"artistName":"Band"},
          {"wrapperType":"track"}
        ]}
        """#
        let items = ITunesCatalog.items(from: Data(json.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(ITunesCatalog.artistFits(items[0], "Band"))
        XCTAssertFalse(ITunesCatalog.artistFits(items[0], "Andere"))
        XCTAssertTrue(ITunesCatalog.artistFits(items[0], ""))
    }

    func testTheCatalogSearchFindsAllKinds() async throws {
        let trackJSON = #"{"results":[{"wrapperType":"track","trackId":7,"trackName":"Tee","artistName":"Band","trackNumber":1}]}"#
        let albumJSON = #"{"results":[{"wrapperType":"collection","collectionName":"Album","collectionId":9,"artistName":"Band"}]}"#
        let search = ITunesCatalogSearch(country: "de") { url in
            url.absoluteString.contains("entity=album") ? Data(albumJSON.utf8) : Data(trackJSON.utf8)
        }
        let song = try await search.find(MusicRequest(action: .play, query: "Tee"))
        XCTAssertEqual(song?.storeIDs, ["7"])
        XCTAssertEqual(song?.pick.kind, .song)
        let artist = try await search.find(MusicRequest(action: .play, query: "Band", kind: .artist))
        XCTAssertEqual(artist?.pick.kind, .artist)
        let album = try await search.find(MusicRequest(action: .play, query: "Album", kind: .album))
        XCTAssertEqual(album?.pick.kind, .album)
        XCTAssertEqual(album?.pick.name, "Album")
        let playlist = try await search.find(MusicRequest(action: .play, query: "Mix", kind: .playlist))
        XCTAssertNil(playlist)
    }

    func testTheSpotifyLinkReadsTheKeychain() {
        let store = GapKeyStore()
        let link = SpotifyLink(clientID: { "client" }, keychain: store)
        XCTAssertFalse(link.signedIn)
        XCTAssertTrue(link.isConfigured)
        store.values[SpotifyConfig.sessionAccount] = "session"
        let signed = SpotifyLink(clientID: { "client" }, keychain: store)
        XCTAssertTrue(signed.signedIn)
        signed.signOut()
        XCTAssertFalse(signed.signedIn)
        XCTAssertTrue(store.values.isEmpty)
        XCTAssertFalse(SpotifyLink(clientID: { "   " }, keychain: store).isConfigured)
        XCTAssertFalse(signed.handle(URL(string: "https://example.test/x")!))
    }
}
