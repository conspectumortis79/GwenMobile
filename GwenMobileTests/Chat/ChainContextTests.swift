@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class StreamWatchdogTests: GwenTestCase {
    func testKeepaliveLinesAloneStallTheWatch() {
        let watch = StreamWatchdog(idle: 1, startedAt: .now - .seconds(30))
        XCTAssertTrue(watch.stalled, "ohne je eine Datenzeile ist die Verbindung nur ein Atemzeichen")
        XCTAssertFalse(watch.sawContent)
    }

    func testContentResetsTheIdleClock() {
        var watch = StreamWatchdog(idle: 30, startedAt: .now - .seconds(30))
        watch.noteContent()
        XCTAssertFalse(watch.stalled, "ein Datenchunk ist Fortschritt")
        XCTAssertTrue(watch.sawContent)
        XCTAssertLessThan(watch.idleFor, 1)
    }

    func testAStreamThatStopsAfterContentIsStillStalled() {
        var watch = StreamWatchdog(idle: 5, startedAt: .now)
        watch.noteContent(at: .now - .seconds(60))
        XCTAssertTrue(watch.stalled)
        XCTAssertTrue(watch.sawContent, "das ist der Fall: Antwort da, [DONE] fehlt")
    }
}

final class ChainContextTests: GwenTestCase {
    private func message(_ role: Role, _ text: String, images: [Attachment] = []) -> ChatMessage {
        ChatMessage(role: role, text: text, images: images)
    }

    func testTheNextStepSeesWhatTheEarlierStepAnswered() {
        let turn = ModelTurn(messages: [message(.user, "Was siehst du und mach es s/w")],
                             images: [Data([1, 2])], pictureFiles: ["img_alt.jpg"])
        let grown = turn.continuing(after: "Ein gelber Stern.", pictures: [Data([3, 4])],
                                    files: ["img_neu.jpg"])
        XCTAssertEqual(grown.messages.count, 2)
        XCTAssertEqual(grown.messages.last?.role, .assistant)
        XCTAssertEqual(grown.messages.last?.text, "Ein gelber Stern.")
        XCTAssertEqual(grown.images.count, 2, "die Stufe danach bearbeitet das neue Bild, nicht das alte")
        XCTAssertEqual(grown.pictureFiles, ["img_alt.jpg", "img_neu.jpg"])
        XCTAssertEqual(grown.positions(of: ["img_neu.jpg"]), [2])
    }

    func testThePictureOfTheNextStepReachesTheLastUserMessage() {
        let turn = ModelTurn(messages: [message(.user, "mach weiter")], images: [], pictureFiles: [])
        let grown = turn.continuing(after: "Bild ist fertig.", pictures: [Data([1])], files: ["neu.jpg"])
        XCTAssertEqual(grown.messages.last(where: { $0.role == .user })?.images.map(\.file), ["neu.jpg"])
        XCTAssertEqual(grown.messages.flatMap(\.images).count, grown.images.count)
    }

    func testAnEmptyAnswerAddsNoHollowMessage() {
        let turn = ModelTurn(messages: [message(.user, "frag")], images: [])
        let grown = turn.continuing(after: "   \n ", pictures: [], files: [])
        XCTAssertEqual(grown.messages.count, 1)
        XCTAssertTrue(grown.images.isEmpty)
        XCTAssertFalse(grown.needsVision)
    }

    func testTheOriginalTurnStaysUntouchedByAChainStep() {
        let turn = ModelTurn(messages: [message(.user, "frag")], images: [Data([9])],
                             pictureFiles: ["a.jpg"])
        _ = turn.continuing(after: "antwort", pictures: [Data([8])], files: ["b.jpg"])
        XCTAssertEqual(turn.messages.count, 1)
        XCTAssertEqual(turn.pictureFiles, ["a.jpg"])
    }

    func testThePictureOfThePreviousStepIsTheNewestTarget() {
        let turn = ModelTurn(messages: [message(.user, "mach weiter")], images: [Data([1])],
                             pictureFiles: ["alt.jpg"], chatPictureCount: 1)
        let grown = turn.continuing(after: "Bild ist fertig.", pictures: [Data([2])], files: ["neu.jpg"])
        XCTAssertTrue(grown.needsVision)
        XCTAssertEqual(grown.pictureCount, 2)
        XCTAssertGreaterThanOrEqual(grown.picturesLeftBehind, 0)
    }
}
