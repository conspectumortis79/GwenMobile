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
        XCTAssertEqual(properties.keys.sorted(),
                       ToolSchemaFields.business(["action", "artist", "kind", "query", "service"]))
        XCTAssertEqual((properties["action"] as? [String: Any])?["enum"] as? [String],
                       ["play", "pause", "resume", "next", "previous"])
        XCTAssertEqual((properties["service"] as? [String: Any])?["enum"] as? [String],
                       ["apple_music", "spotify", "any"])
    }

    func testTheDescriptionKeepsQuestionsAboutMusicAndPicturesAway() throws {
        let description = try XCTUnwrap(try musicFunction()["description"] as? String)
        XCTAssertTrue(description.contains("answer_in_chat or search_web"), description)
        XCTAssertTrue(description.contains(ToolRouter.findTool), description)
        XCTAssertTrue(description.contains("only from the user's words"), description)
        XCTAssertTrue(description.contains("is pause, never play or resume"), description)
        XCTAssertTrue(description.contains("off, out or away"), description)
    }

    func testTheRouterPolicyNamesTheMusicTool() {
        let system = ToolRouter.systemBlock(now: "heute", context: SendContext(), transcript: "")
        XCTAssertTrue(system.contains("Use \(ToolRouter.musicTool) whenever"), system)
        XCTAssertTrue(system.contains("a command for off or no sound are pause"), system)
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

    func testABarePlayRightBeforeAPauseIsDropped() {
        let plan = SendPlan.forming([ToolDecision(route: .music(MusicRequest(action: .play))),
                                     ToolDecision(route: .music(MusicRequest(action: .pause)))])
        XCTAssertEqual(plan.traceLine, "music",
                       "ohne Suchbegriff ist das Starten eine leere Geste vor dem Pausieren")
        let kept = SendPlan.forming([ToolDecision(route: .music(MusicRequest(action: .play, query: "Hello"))),
                                     ToolDecision(route: .music(MusicRequest(action: .pause)))])
        XCTAssertEqual(kept.traceLine, "music+music")
        let separated = SendPlan.forming([ToolDecision(route: .music(MusicRequest(action: .play))),
                                          ToolDecision(route: .chat),
                                          ToolDecision(route: .music(MusicRequest(action: .pause)))])
        XCTAssertEqual(separated.traceLine, "chat+music",
                       "auch ein dazwischenliegender Schritt hebt die leere Geste nicht auf")
    }

    func testTheStepKeyCarriesTheWholeWish() {
        let step = ToolDecision(route: .music(MusicRequest(action: .play, query: "Hello", artist: "Adele",
                                                           kind: .song, service: .spotify)))
        XCTAssertEqual(step.stepKey, "music|play hello adele song spotify")
    }

    func testTheSplitterKnowsMusicIsAWishOfItsOwn() {
        XCTAssertTrue(WishSplitter.system().contains("play or control music once"), WishSplitter.system())
    }

    func testAResumeWithoutATitleDropsOutWhenTheSamePlanPauses() {
        let play = ToolDecision(route: .music(MusicRequest(action: .play)))
        let pause = ToolDecision(route: .music(MusicRequest(action: .pause)))
        let plan = SendPlan.forming([play, pause])
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.primary.route, .music(MusicRequest(action: .pause)))
        XCTAssertEqual(SendPlan.forming([play, ToolDecision(route: .music(MusicRequest(action: .next)))])
            .actions.count, 2)
        XCTAssertEqual(SendPlan.forming([play, ToolDecision(route: .music(MusicRequest(action: .next))), pause])
            .actions.count, 3)
        XCTAssertEqual(SendPlan.forming([ToolDecision(route: .music(MusicRequest(action: .play,
                                                                           query: "Hello"))), pause])
            .actions.count, 2)
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
