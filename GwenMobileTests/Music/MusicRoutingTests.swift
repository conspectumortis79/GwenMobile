@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class MusicRoutingTests: GwenTestCase {
    private func musicFunction() throws -> [String: Any] {
        try toolFunction(ToolRouter.musicTool)
    }

    private func decision(_ arguments: String) -> ToolDecision? {
        ToolRouter.map(name: ToolRouter.musicTool, arguments: arguments)
    }

    func testTheMusicToolIsOfferedWithTheClosedLists() throws {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: true)).contains(ToolRouter.musicTool))
        let parameters = try XCTUnwrap(try musicFunction()["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], ["action"])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertEqual(properties.keys.sorted(), ["action", "artist", "kind", "query", "service"])
        XCTAssertEqual((properties["action"] as? [String: Any])?["enum"] as? [String],
                       ["play", "pause", "resume", "next", "previous"])
        XCTAssertEqual((properties["service"] as? [String: Any])?["enum"] as? [String],
                       ["apple_music", "spotify", "any"])
    }

    func testTheDescriptionKeepsQuestionsAboutMusicAndPicturesAway() throws {
        let description = try XCTUnwrap(try musicFunction()["description"] as? String)
        XCTAssertTrue(description.contains("answer_in_chat or search_web"), description)
        XCTAssertTrue(description.contains(ToolRouter.findTool), description)
        XCTAssertTrue(description.contains("never from these examples"), description)
        XCTAssertTrue(description.contains("\"Musik aus\""), description)
        XCTAssertTrue(description.contains("is pause, never play"), description)
    }

    func testTheRouterPolicyNamesTheMusicTool() {
        let system = ToolRouter.systemBlock(now: "heute", context: SendContext(), transcript: "")
        XCTAssertTrue(system.contains("Use \(ToolRouter.musicTool) whenever"), system)
        XCTAssertTrue(system.contains("\"Musik aus\"") && system.contains("is pause"), system)
    }

    func testAPlaylistWishBecomesAMusicRouteWithEveryField() {
        XCTAssertEqual(decision(#"{"action":"play","query":"Sport","kind":"playlist","service":"spotify"}"#)?.route,
                       .music(MusicRequest(action: .play, query: "Sport", kind: .playlist, service: .spotify)))
        XCTAssertEqual(decision(#"{"action":"play","query":"Hello","artist":"Adele","kind":"song"}"#)?.route,
                       .music(MusicRequest(action: .play, query: "Hello", artist: "Adele", kind: .song)))
        XCTAssertEqual(decision(#"{"action":"next"}"#)?.stepKind, .music)
    }

    func testUnknownValuesStayOpenAndAMissingActionIsNoMusic() {
        XCTAssertEqual(decision(#"{"action":"PAUSE","kind":"hörbuch","service":"any"}"#)?.route,
                       .music(MusicRequest(action: .pause)))
        XCTAssertEqual(decision(#"{"query":"Sport"}"#)?.route, .chat)
        XCTAssertEqual(decision("kein json")?.route, .chat)
    }

    func testMusicRunsAfterTheOtherWishesAndBeforeACall() {
        let plan = SendPlan.forming([ToolDecision(route: .call(ContactRequest(person: "Mama"))),
                                     ToolDecision(route: .music(MusicRequest(action: .pause))),
                                     ToolDecision(route: .clock(ClockRequest()))])
        XCTAssertEqual(plan.traceLine, "clock+music+call")
        XCTAssertFalse(plan.merges, "eine vorgelesene Sammelantwort würde über die Musik sprechen")
    }

    func testTheStepKeyCarriesTheWholeWish() {
        let step = ToolDecision(route: .music(MusicRequest(action: .play, query: "Hello", artist: "Adele",
                                                           kind: .song, service: .spotify)))
        XCTAssertEqual(step.stepKey, "music|play hello adele song spotify")
    }

    func testTheSplitterKnowsMusicIsAWishOfItsOwn() {
        XCTAssertTrue(WishSplitter.system().contains("play or control music once"), WishSplitter.system())
    }

    func testTheTermFallsBackToTheArtist() {
        XCTAssertEqual(MusicRequest(action: .play, query: " ", artist: "Adele", kind: .artist).term, "Adele")
        XCTAssertEqual(MusicRequest(action: .play, query: "Hello", artist: "Adele").term, "Hello")
        XCTAssertFalse(MusicRequest(action: .play).wantsSomething)
    }
}

final class MusicServiceChoiceTests: XCTestCase {
    func testANamedServiceAlwaysWins() {
        XCTAssertEqual(MusicServiceChoice.pick(MusicRequest(action: .pause, service: .appleMusic),
                                               playing: [.spotify], lastUsed: .spotify, preferred: .spotify),
                       .appleMusic)
    }

    func testAWishWithATitleGoesToThePreferredService() {
        XCTAssertEqual(MusicServiceChoice.pick(MusicRequest(action: .play, query: "Sport"),
                                               playing: [.spotify], lastUsed: .spotify, preferred: .appleMusic),
                       .appleMusic)
    }

    func testACommandGoesToWhatPlaysThenToTheLastOneThenToThePreferred() {
        let pause = MusicRequest(action: .pause)
        XCTAssertEqual(MusicServiceChoice.pick(pause, playing: [.spotify], lastUsed: .appleMusic,
                                               preferred: .appleMusic), .spotify)
        XCTAssertEqual(MusicServiceChoice.pick(pause, playing: [], lastUsed: .spotify, preferred: .appleMusic),
                       .spotify)
        XCTAssertEqual(MusicServiceChoice.pick(pause, playing: [], lastUsed: nil, preferred: .spotify), .spotify)
        XCTAssertEqual(MusicServiceChoice.pick(MusicRequest(action: .play), playing: [], lastUsed: .spotify,
                                               preferred: .appleMusic), .spotify, "Musik weiter heißt: dort weiter")
    }
}
