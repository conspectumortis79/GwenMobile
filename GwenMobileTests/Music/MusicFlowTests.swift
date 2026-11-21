@testable import GwenMobileFeatureCore
#if !targetEnvironment(macCatalyst)
import XCTest
import GwenMobileKit

@MainActor
private final class FakeSource: MusicSource {
    var isPlaying = false
    var answer: MusicOutcome = .resumed
    private(set) var played: [MusicRequest] = []
    private(set) var controlled: [MusicAction] = []

    func play(_ request: MusicRequest) async -> MusicOutcome {
        played.append(request)
        return answer
    }

    func control(_ action: MusicAction) async -> MusicOutcome {
        controlled.append(action)
        return .controlled(action)
    }
}

private struct FakeLibrary: MusicLibraryReading {
    var granted = true
    var stored: [MusicLibraryEntry] = []

    func access() async -> Bool { granted }

    func entries(of kinds: [MusicKind]) async -> [MusicLibraryEntry] { stored.filter { kinds.contains($0.kind) } }
}

private struct FakeCatalog: MusicCatalogSearching {
    var found: CatalogPick?
    var broken = false

    func find(_ request: MusicRequest) async throws -> CatalogPick? {
        if broken { throw APIError(message: "netz weg") }
        return found
    }
}

@MainActor
private final class FakeApp: MusicAppPlaying {
    var isPlaying = false
    var works = true
    private(set) var entries: [MusicLibraryEntry] = []
    private(set) var storeIDs: [[String]] = []
    private(set) var actions: [MusicAction] = []

    func play(_ entry: MusicLibraryEntry) async -> Bool {
        entries.append(entry)
        return works
    }

    func play(storeIDs: [String]) async -> Bool {
        self.storeIDs.append(storeIDs)
        return works
    }

    func perform(_ action: MusicAction) { actions.append(action) }
}

@MainActor
final class MusicFlowRunnerTests: GwenTestCase {
    func testTheAppleSourceReportsItsPlayingState() {
        let source = AppleMusicSource(library: FakeLibrary(), catalog: FakeCatalog(), app: FakeApp())
        XCTAssertFalse(source.isPlaying)
    }

    func testAWishGoesToThePreferredServiceAndNamesWhatPlays() async {
        let apple = FakeSource()
        apple.answer = .playing(MusicPick(kind: .playlist, name: "Sport"))
        let runner = MusicFlowRunner(sources: [.appleMusic: apple, .spotify: FakeSource()],
                                     preferred: .appleMusic, lastUsed: nil)
        let outcome = await runner.run(MusicRequest(action: .play, query: "Sport", kind: .playlist))
        XCTAssertEqual(apple.played.map(\.term), ["Sport"])
        XCTAssertEqual(outcome.text, "🎵 Playing the playlist “Sport” on Apple Music.")
        XCTAssertTrue(outcome.soundsNow, "was schon klingt, wird nicht zusätzlich vorgelesen")
    }

    func testACommandReachesTheServiceThatIsPlaying() async {
        let apple = FakeSource()
        let spotify = FakeSource()
        spotify.isPlaying = true
        let outcome = await MusicFlowRunner(sources: [.appleMusic: apple, .spotify: spotify], preferred: .appleMusic,
                                            lastUsed: nil).run(MusicRequest(action: .next))
        XCTAssertEqual(spotify.controlled, [.next])
        XCTAssertTrue(apple.controlled.isEmpty)
        XCTAssertEqual(outcome.text, "⏭ Next title on Spotify.")
    }

    func testAServiceTheDeviceCannotUseIsNamedInsteadOfSilence() async {
        let outcome = await MusicFlowRunner(sources: [:], preferred: .spotify, lastUsed: nil)
            .run(MusicRequest(action: .play, query: "Adele"))
        XCTAssertEqual(outcome.text, "Spotify cannot be controlled in this version of GwenMobile.")
        XCTAssertFalse(outcome.soundsNow)
    }

    func testEveryAnswerTextNamesItsService() {
        let pick = MusicPick(kind: .song, name: "Hello", artist: "Adele")
        XCTAssertEqual(MusicAnswer.text(.playing(pick), service: .appleMusic),
                       "🎵 Playing “Hello – Adele” on Apple Music.")
        XCTAssertEqual(MusicAnswer.text(.playing(MusicPick(kind: .artist, name: "Adele")),
                                        service: .spotify), "🎵 Playing music by Adele on Spotify.")
        XCTAssertEqual(MusicAnswer.text(.controlled(.pause), service: .spotify), "⏸ The music on Spotify is paused.")
        XCTAssertEqual(MusicAnswer.text(.notFound("Sport"), service: .appleMusic),
                       "I found nothing for “Sport” on Apple Music.")
        XCTAssertEqual(MusicAnswer.text(.openedApp(pick), service: .spotify),
                       "🎵 Spotify opens and plays “Hello – Adele”.")
        XCTAssertFalse(MusicOutcome.notSetUp.soundsNow)
        XCTAssertTrue(MusicOutcome.controlled(.pause).soundsNow)
    }

    func testTheDeskRemembersOnlyAServiceThatReallyPlays() {
        let desk = MusicDesk(sources: [:])
        desk.remember(MusicFlowOutcome(text: "", service: .spotify, soundsNow: false, trace: ""))
        XCTAssertNil(desk.lastUsed)
        desk.remember(MusicFlowOutcome(text: "", service: .spotify, soundsNow: true, trace: ""))
        XCTAssertEqual(desk.lastUsed, .spotify)
    }

    func testTheDeskSwapsInSilentSourcesAndRestoresTheLiveOnes() {
        let live = FakeSource()
        let desk = MusicDesk(sources: [.appleMusic: live])
        desk.stand(in: [:])
        XCTAssertTrue(desk.sources.isEmpty)
        desk.restore()
        XCTAssertTrue(desk.sources[.appleMusic] as? FakeSource === live)
    }
}

@MainActor
final class AppleMusicSourceTests: GwenTestCase {
    private let sport = MusicLibraryEntry(kind: .playlist, id: 7, name: "Sport")

    func testWithoutLibraryAccessNothingIsSearchedOrPlayed() async {
        let app = FakeApp()
        let source = AppleMusicSource(library: FakeLibrary(granted: false), catalog: FakeCatalog(), app: app)
        let outcome = await source.play(MusicRequest(action: .play, query: "Sport"))
        XCTAssertEqual(outcome, .libraryDenied)
        XCTAssertTrue(app.entries.isEmpty && app.storeIDs.isEmpty)
    }

    func testPlainMusicResumesTheMusicApp() async {
        let app = FakeApp()
        let outcome = await AppleMusicSource(library: FakeLibrary(), catalog: FakeCatalog(), app: app)
            .play(MusicRequest(action: .play))
        XCTAssertEqual(outcome, .resumed)
        XCTAssertEqual(app.actions, [.resume])
    }

    func testTheOwnLibraryComesBeforeTheCatalog() async {
        let app = FakeApp()
        let catalog = FakeCatalog(found: CatalogPick(storeIDs: ["1"],
                                                     pick: MusicPick(kind: .song, name: "Sport")))
        let outcome = await AppleMusicSource(library: FakeLibrary(stored: [sport]), catalog: catalog, app: app)
            .play(MusicRequest(action: .play, query: "sport", kind: .playlist))
        XCTAssertEqual(outcome, .playing(sport.pick))
        XCTAssertEqual(app.entries, [sport])
        XCTAssertTrue(app.storeIDs.isEmpty)
    }

    func testTheCatalogStepsInWhenTheLibraryHasNothing() async {
        let app = FakeApp()
        let hello = MusicPick(kind: .song, name: "Hello", artist: "Adele")
        let outcome = await AppleMusicSource(library: FakeLibrary(),
                                             catalog: FakeCatalog(found: CatalogPick(storeIDs: ["1051333148"], pick: hello)),
                                             app: app).play(MusicRequest(action: .play, query: "Hello", artist: "Adele"))
        XCTAssertEqual(outcome, .playing(hello))
        XCTAssertEqual(app.storeIDs, [["1051333148"]])
    }

    func testACatalogTitleWithoutSubscriptionIsExplained() async {
        let app = FakeApp()
        app.works = false
        let hello = MusicPick(kind: .song, name: "Hello")
        let outcome = await AppleMusicSource(library: FakeLibrary(),
                                             catalog: FakeCatalog(found: CatalogPick(storeIDs: ["1"], pick: hello)),
                                             app: app).play(MusicRequest(action: .play, query: "Hello"))
        XCTAssertEqual(outcome, .catalogRefused("Hello"))
    }

    func testNothingAnywhereIsNotFoundAndABrokenNetIsAFailure() async {
        let quiet = await AppleMusicSource(library: FakeLibrary(), catalog: FakeCatalog(), app: FakeApp())
            .play(MusicRequest(action: .play, query: "Gibtsnicht"))
        XCTAssertEqual(quiet, .notFound("Gibtsnicht"))
        let broken = await AppleMusicSource(library: FakeLibrary(), catalog: FakeCatalog(broken: true), app: FakeApp())
            .play(MusicRequest(action: .play, query: "Hello"))
        guard case .failed = broken else { return XCTFail("\(broken)") }
    }

    func testCommandsGoStraightToTheMusicApp() async {
        let app = FakeApp()
        let source = AppleMusicSource(library: FakeLibrary(), catalog: FakeCatalog(), app: app)
        let paused = await source.control(.pause)
        let resumed = await source.control(.resume)
        XCTAssertEqual(paused, .controlled(.pause))
        XCTAssertEqual(resumed, .resumed)
        XCTAssertEqual(app.actions, [.pause, .resume])
    }
}

final class MusicLibraryMatchingTests: XCTestCase {
    private let entries = [MusicLibraryEntry(kind: .playlist, id: 1, name: "Sport am Morgen"),
                           MusicLibraryEntry(kind: .playlist, id: 2, name: "Sport"),
                           MusicLibraryEntry(kind: .artist, id: 3, name: "Adele"),
                           MusicLibraryEntry(kind: .song, id: 4, name: "Hello", artist: "Lionel Richie"),
                           MusicLibraryEntry(kind: .song, id: 5, name: "Hello", artist: "Adele"),
                           MusicLibraryEntry(kind: .album, id: 6, name: "21", artist: "Adele")]

    private func best(_ request: MusicRequest) -> UInt64? {
        MusicLibraryMatching.best(for: request, in: entries)?.id
    }

    func testAnExactNameBeatsALongerOne() {
        XCTAssertEqual(best(MusicRequest(action: .play, query: "sport", kind: .playlist)), 2)
    }

    func testTheArtistTellsTwoEqualTitlesApart() {
        XCTAssertEqual(best(MusicRequest(action: .play, query: "Hello", artist: "Adele", kind: .song)), 5)
    }

    func testAnOpenKindSearchesPlaylistsArtistsAlbumsAndSongsInThatOrder() {
        XCTAssertEqual(best(MusicRequest(action: .play, query: "Adele")), 3)
        XCTAssertEqual(best(MusicRequest(action: .play, query: "21")), 6)
    }

    func testEveryWordHasToFitAndNothingIsGuessed() {
        XCTAssertNil(best(MusicRequest(action: .play, query: "Sport am Abend", kind: .playlist)))
        XCTAssertNil(best(MusicRequest(action: .play, query: "", kind: .playlist)))
    }
}
#endif
