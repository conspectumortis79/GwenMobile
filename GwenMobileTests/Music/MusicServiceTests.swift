@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
private final class FakeAuth: SpotifyAuthorizing {
    var isConfigured = true
    var token: String? = "tok"

    func accessToken() async -> String? { token }
}

@MainActor
private final class FakeRemote: SpotifyRemoteControlling {
    var isConnected = false
    var isPlaying = false
    var connects = false
    var works = true
    var appInstalled = true
    private(set) var played: [String] = []
    private(set) var actions: [MusicAction] = []
    private(set) var woken: [String] = []

    func connect(token: String) async -> Bool {
        if connects { isConnected = true }
        return connects
    }

    func play(uri: String) async -> Bool {
        played.append(uri)
        return works
    }

    func perform(_ action: MusicAction) async -> Bool {
        actions.append(action)
        return works
    }

    func wakeAndPlay(uri: String) async -> Bool {
        woken.append(uri)
        return appInstalled
    }
}

private final class FakeWeb: SpotifyWebControlling, @unchecked Sendable {
    var target: SpotifyTarget?
    var findFailure: Error?
    var result: SpotifyWebResult = .done
    private(set) var plays: [String?] = []
    private(set) var actions: [MusicAction] = []

    func find(_ request: MusicRequest, token: String) async throws -> SpotifyTarget? {
        if let findFailure { throw findFailure }
        return target
    }

    func play(_ target: SpotifyTarget?, token: String) async throws -> SpotifyWebResult {
        plays.append(target?.uri)
        return result
    }

    func perform(_ action: MusicAction, token: String) async throws -> SpotifyWebResult {
        actions.append(action)
        return result
    }
}

@MainActor
final class SpotifySourceTests: GwenTestCase {
    private let hello = SpotifyTarget(uri: "spotify:track:abc",
                                      pick: MusicPick(kind: .song, name: "Hello", artist: "Adele"))
    private let request = MusicRequest(action: .play, query: "Hello", artist: "Adele", kind: .song)

    private func source(_ remote: FakeRemote, _ web: FakeWeb, auth: FakeAuth = FakeAuth(),
                        active: Bool = true) -> SpotifySource {
        SpotifySource(auth: auth, remote: remote, web: web, isActive: { active })
    }

    func testThePlayingStateAndAWebFailure() async {
        let remote = FakeRemote()
        remote.isPlaying = true
        let web = FakeWeb()
        XCTAssertTrue(source(remote, web).isPlaying)
        web.findFailure = APIError(message: "suche kaputt")
        let outcome = await source(remote, web).play(request)
        guard case .failed(let text) = outcome else {
            XCTFail("erwartet Fehler")
            return
        }
        XCTAssertTrue(text.contains("suche kaputt"))
    }

    func testWithoutClientIDOrLoginNothingIsSent() async {
        let web = FakeWeb()
        let unset = FakeAuth()
        unset.isConfigured = false
        let first = await source(FakeRemote(), web, auth: unset).play(request)
        XCTAssertEqual(first, .notSetUp)
        let loggedOut = FakeAuth()
        loggedOut.token = nil
        let second = await source(FakeRemote(), web, auth: loggedOut).control(.pause)
        XCTAssertEqual(second, .notConnected)
        XCTAssertTrue(web.plays.isEmpty && web.actions.isEmpty)
    }

    func testAConnectedRemotePlaysTheFoundTitleDirectly() async {
        let remote = FakeRemote()
        remote.isConnected = true
        let web = FakeWeb()
        web.target = hello
        let outcome = await source(remote, web).play(request)
        XCTAssertEqual(outcome, .playing(hello.pick))
        XCTAssertEqual(remote.played, ["spotify:track:abc"])
        XCTAssertTrue(web.plays.isEmpty)
    }

    func testInTheForegroundTheRemoteConnectsFirstAndOnlyThenWakesSpotify() async {
        let remote = FakeRemote()
        remote.connects = true
        let web = FakeWeb()
        web.target = hello
        let connected = await source(remote, web).play(request)
        XCTAssertEqual(connected, .playing(hello.pick))
        XCTAssertTrue(remote.woken.isEmpty)
        let sleeping = FakeRemote()
        let woken = await source(sleeping, web).play(request)
        XCTAssertEqual(woken, .openedApp(hello.pick))
        XCTAssertEqual(sleeping.woken, ["spotify:track:abc"])
    }

    func testWithoutTheSpotifyAppTheWakeUpFailsWithAReason() async {
        let remote = FakeRemote()
        remote.appInstalled = false
        let web = FakeWeb()
        web.target = hello
        let outcome = await source(remote, web).play(request)
        XCTAssertEqual(outcome, .failed(L.t("music_spotify_missing_app")))
    }

    func testInTheBackgroundTheWebAPIPlaysWithoutAnAppSwitch() async {
        let remote = FakeRemote()
        let web = FakeWeb()
        web.target = hello
        let outcome = await source(remote, web, active: false).play(request)
        XCTAssertEqual(outcome, .playing(hello.pick))
        XCTAssertEqual(web.plays, ["spotify:track:abc"])
        XCTAssertTrue(remote.woken.isEmpty, "im Hintergrund darf kein App-Wechsel versucht werden")
    }

    func testARefusalOfSpotifyIsShownWithItsOwnMessage() async {
        let web = FakeWeb()
        web.target = hello
        web.result = .refused("Player command failed: No active device found")
        let outcome = await source(FakeRemote(), web, active: false).play(request)
        XCTAssertEqual(outcome, .failed("Player command failed: No active device found"))
    }

    func testNothingFoundIsNeverPlayed() async {
        let remote = FakeRemote()
        remote.isConnected = true
        let outcome = await source(remote, FakeWeb()).play(request)
        XCTAssertEqual(outcome, .notFound("Hello"))
        XCTAssertTrue(remote.played.isEmpty)
    }

    func testPlainMusicResumesWithoutSearching() async {
        let remote = FakeRemote()
        remote.isConnected = true
        let outcome = await source(remote, FakeWeb()).play(MusicRequest(action: .play))
        XCTAssertEqual(outcome, .resumed)
        XCTAssertEqual(remote.actions, [.resume])
    }

    func testCommandsUseTheRemoteAndFallBackToTheWebAPI() async {
        let remote = FakeRemote()
        remote.isConnected = true
        let web = FakeWeb()
        let direct = await source(remote, web).control(.next)
        XCTAssertEqual(direct, .controlled(.next))
        XCTAssertEqual(remote.actions, [.next])
        let away = FakeRemote()
        let fromWeb = await source(away, web, active: true).control(.pause)
        XCTAssertEqual(fromWeb, .controlled(.pause))
        XCTAssertEqual(web.actions, [.pause], "ohne Verbindung übernimmt die Web-API")
    }

    func testTheWayDependsOnConnectionAndForeground() {
        XCTAssertEqual(SpotifyWay.pick(connected: true, active: false), .remote)
        XCTAssertEqual(SpotifyWay.pick(connected: false, active: true), .connectFirst)
        XCTAssertEqual(SpotifyWay.pick(connected: false, active: false), .web)
    }

    func testOnlyTheOwnCallbackIsTakenAsSpotifyLogin() {
        XCTAssertTrue(SpotifyConfig.isCallback(URL(string: "gwenmobile://spotify-login-callback?code=x")!))
        XCTAssertFalse(SpotifyConfig.isCallback(URL(string: "gwenmobile://listen")!))
        XCTAssertFalse(SpotifyConfig.isCallback(URL(string: "other://spotify-login-callback")!))
        XCTAssertEqual(SpotifyConfig.redirectURI, "gwenmobile://spotify-login-callback")
    }
}

final class SpotifyWebAPITests: XCTestCase {
    private func query(_ request: URLRequest?) -> [String: String] {
        let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testTheSearchStaysWithinTheDevModeLimitAndFiltersByArtist() {
        let search = SpotifyWebAPI.search(MusicRequest(action: .play, query: "Hello", artist: "Adele", kind: .song),
                                          token: "tok")
        XCTAssertEqual(query(search), ["q": "Hello artist:Adele", "type": "track", "limit": "10"])
        XCTAssertEqual(search?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(query(SpotifyWebAPI.search(MusicRequest(action: .play, query: "Adele", kind: .artist),
                                                  token: "tok"))["type"], "artist")
    }

    func testATrackIsPlayedAsUrisAndEverythingElseAsContext() throws {
        let track = SpotifyTarget(uri: "spotify:track:1", pick: MusicPick(kind: .song, name: "a"))
        let list = SpotifyTarget(uri: "spotify:playlist:2", pick: MusicPick(kind: .playlist, name: "b"))
        let first = try XCTUnwrap(SpotifyWebAPI.play(track, token: "t"))
        XCTAssertEqual(first.httpMethod, "PUT")
        XCTAssertEqual(first.url?.absoluteString, "https://api.spotify.com/v1/me/player/play")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: first.httpBody ?? Data()) as? [String: [String]],
                       ["uris": ["spotify:track:1"]])
        let second = try XCTUnwrap(SpotifyWebAPI.play(list, token: "t"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: second.httpBody ?? Data()) as? [String: String],
                       ["context_uri": "spotify:playlist:2"])
        XCTAssertNil(SpotifyWebAPI.play(nil, token: "t")?.httpBody, "ohne Ziel spielt Spotify einfach weiter")
    }

    func testEveryCommandHasItsDocumentedMethodAndPath() {
        let pause = SpotifyWebAPI.control(.pause, token: "t")
        XCTAssertEqual(pause?.httpMethod, "PUT")
        XCTAssertEqual(pause?.url?.path, "/v1/me/player/pause")
        XCTAssertEqual(SpotifyWebAPI.control(.next, token: "t")?.httpMethod, "POST")
        XCTAssertEqual(SpotifyWebAPI.control(.previous, token: "t")?.url?.path, "/v1/me/player/previous")
        XCTAssertEqual(SpotifyWebAPI.control(.resume, token: "t")?.url?.path, "/v1/me/player/play")
    }

    func testSearchResultsAndOwnPlaylistsAreRead() {
        let search = Data(#"{"tracks":{"items":[{"uri":"spotify:track:1","name":"Hello","artists":[{"name":"Adele"}]}]}}"#.utf8)
        XCTAssertEqual(SpotifyWebAPI.targets(from: search, kind: .song).first,
                       SpotifyTarget(uri: "spotify:track:1",
                                     pick: MusicPick(kind: .song, name: "Hello", artist: "Adele")))
        let own = Data(#"{"items":[null,{"uri":"spotify:playlist:9","name":"Sport am Morgen"},{"uri":"spotify:playlist:8","name":"Sport"}]}"#.utf8)
        let playlists = SpotifyWebAPI.targets(from: own, kind: .playlist)
        XCTAssertEqual(playlists.count, 2, "leere Einträge der Antwort werden übergangen")
        XCTAssertEqual(SpotifyWebAPI.bestPlaylist("sport", in: playlists)?.uri, "spotify:playlist:8")
    }

    func testSpotifysOwnErrorMessageIsRead() {
        XCTAssertEqual(SpotifyWebAPI.errorMessage(from: Data(#"{"error":{"status":404,"message":"No active device"}}"#.utf8)),
                       "No active device")
        XCTAssertNil(SpotifyWebAPI.errorMessage(from: Data("kaputt".utf8)))
    }
}

final class ITunesCatalogTests: XCTestCase {
    private let songs = Data(#"{"resultCount":2,"results":[{"wrapperType":"track","kind":"song","trackId":1051333148,"trackName":"Hello","artistName":"Adele","collectionId":1051332740,"trackNumber":1},{"wrapperType":"track","kind":"song","trackId":7,"trackName":"Hello","artistName":"Lionel Richie","collectionId":8,"trackNumber":3}]}"#.utf8)

    func testTheSearchURLCarriesTermEntityLimitAndCountry() throws {
        let url = try XCTUnwrap(ITunesCatalog.searchURL(term: "Hello Adele", entity: "song", attribute: "artistTerm",
                                                        limit: 10, country: "de"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(url.host, "itunes.apple.com")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }),
                       ["term": "Hello Adele", "media": "music", "entity": "song", "limit": "10", "country": "de",
                        "attribute": "artistTerm"])
    }

    func testTheCountryComesFromTheDeviceRegion() {
        XCTAssertEqual(ITunesCatalog.country(Locale(identifier: "de_DE")), "de")
    }

    func testTracksAndAlbumsAreRead() {
        XCTAssertEqual(ITunesCatalog.items(from: songs).map(\.trackID), [1051333148, 7])
        let album = Data(#"{"results":[{"wrapperType":"collection","collectionId":403037872,"collectionName":"21","artistName":"Adele"}]}"#.utf8)
        XCTAssertEqual(ITunesCatalog.items(from: album).first,
                       ITunesItem(trackID: nil, collectionID: 403037872, name: "21", artist: "Adele", trackNumber: nil))
    }

    func testTheNamedArtistPicksTheRightSong() async throws {
        let data = songs
        let search = ITunesCatalogSearch(country: "de", fetch: { _ in data })
        let found = try await search.find(MusicRequest(action: .play, query: "Hello", artist: "Lionel Richie", kind: .song))
        XCTAssertEqual(found?.storeIDs, ["7"])
    }

    func testAnAlbumIsLookedUpAndPlayedInTrackOrder() async throws {
        let album = Data(#"{"results":[{"wrapperType":"collection","collectionId":5,"collectionName":"21","artistName":"Adele"}]}"#.utf8)
        let tracks = Data(#"{"results":[{"wrapperType":"collection","collectionId":5,"collectionName":"21"},{"wrapperType":"track","trackId":12,"trackName":"b","artistName":"Adele","trackNumber":2},{"wrapperType":"track","trackId":11,"trackName":"a","artistName":"Adele","trackNumber":1}]}"#.utf8)
        let search = ITunesCatalogSearch(country: "de", fetch: { url in url.path == "/lookup" ? tracks : album })
        let found = try await search.find(MusicRequest(action: .play, query: "21", artist: "Adele", kind: .album))
        XCTAssertEqual(found?.storeIDs, ["11", "12"])
        XCTAssertEqual(found?.pick.name, "21")
    }

    func testAnArtistKeepsOnlyTheirOwnSongsAndPlaylistsAreNotInTheCatalog() async throws {
        let data = songs
        let search = ITunesCatalogSearch(country: "de", fetch: { _ in data })
        let artist = try await search.find(MusicRequest(action: .play, query: "Adele", kind: .artist))
        XCTAssertEqual(artist?.storeIDs, ["1051333148"])
        let playlist = try await search.find(MusicRequest(action: .play, query: "Sport", kind: .playlist))
        XCTAssertNil(playlist)
    }
}
