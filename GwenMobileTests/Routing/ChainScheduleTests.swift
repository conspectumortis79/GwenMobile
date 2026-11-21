@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ChainScheduleTests: GwenTestCase {
    private func step(_ route: SendRoute, standalone: Bool = true) -> ToolDecision {
        var decision = ToolDecision(route: route)
        decision.standalone = standalone
        return decision
    }

    private var chat: ToolDecision { step(.chat) }
    private var clock: ToolDecision { step(.clock(ClockRequest(timeZone: "Asia/Tokyo", place: nil))) }
    private var weather: ToolDecision { step(.weather(WeatherRequest(place: "Berlin", day: .today, date: nil))) }
    private var calendar: ToolDecision { step(.calendar) }
    private var history: ToolDecision { step(.history) }

    private func picture(_ words: String, _ standalone: Bool, edit: Bool = false) -> ToolDecision {
        var decision = edit
            ? ToolDecision(route: .imageEdit, pictureInstruction: words, pictureMonochrome: true)
            : ToolDecision(route: .imageCreate, picturePrompt: words)
        decision.wish = words
        decision.standalone = standalone
        return decision
    }

    func testEveryKindKnowsWhetherItMayRunBesideAnotherStep() {
        let network: Set<SendStepKind> = [.chat, .search, .gallery, .code, .weather, .clock, .price,
                                          .briefing, .status, .create]
        for kind in SendStepKind.allCases {
            let alone = network.contains(kind) || kind == .translate
            XCTAssertEqual(ChainSchedule.runsConcurrently(kind, translatesFromChat: false),
                           alone, kind.rawValue)
            XCTAssertEqual(ChainSchedule.runsConcurrently(kind, translatesFromChat: true),
                           network.contains(kind), kind.rawValue)
        }
        XCTAssertFalse(ChainSchedule.runsConcurrently(.translate, translatesFromChat: true))
        XCTAssertTrue(ChainSchedule.runsConcurrently(.translate, translatesFromChat: false))
    }

    func testOnlyAWishThatNeedsNothingEarlierMayRunBesideAnother() {
        XCTAssertFalse(ChainSchedule.runsConcurrently(step(.chat, standalone: false)),
                       "ohne Zerlegung bleibt jeder Schritt in seiner Reihenfolge")
        XCTAssertTrue(ChainSchedule.runsConcurrently(chat))
        XCTAssertFalse(ChainSchedule.runsConcurrently(step(.calendar)),
                       "ein Termin schreibt auf das Gerät und bleibt allein")
        XCTAssertTrue(ChainSchedule.runsConcurrently(step(.imageCreate)),
                      "drei getrennte Bilder dürfen zusammen entstehen")
        XCTAssertFalse(ChainSchedule.runsConcurrently(step(.imageEdit)),
                       "eine Bearbeitung hängt am Bild, das sie ändert")
        var fromChat = step(.translate(TranslationJob(text: "", targetCode: "en", fromChat: true)))
        XCTAssertFalse(ChainSchedule.runsConcurrently(fromChat), "eine Übersetzung des Verlaufs liest ihn")
        fromChat.route = .translate(TranslationJob(text: "Hallo", targetCode: "en"))
        XCTAssertTrue(ChainSchedule.runsConcurrently(fromChat))
        XCTAssertFalse(step(.chat).translatesFromChat, "nur die Übersetzung trägt diese Angabe")
    }

    func testTwoUnrelatedStepsShareOneStageAndKeepTheirOrder() {
        let stages = ChainSchedule.stages([chat, clock, weather])
        XCTAssertEqual(stages, [[0, 1, 2]], "drei unabhängige Netzschnitte laufen zusammen")
    }

    func testADeviceStepStaysAloneAndIndependentStepsGoAhead() {
        XCTAssertEqual(ChainSchedule.stages([chat, calendar, clock]), [[0, 2], [1]],
                       "der unabhängige Schritt wartet nicht auf den Termin")
        XCTAssertEqual(ChainSchedule.stages([calendar, chat, clock]), [[1, 2], [0]],
                       "der Termin bleibt allein, die zwei Fragen laufen zusammen")
        XCTAssertEqual(ChainSchedule.stages([chat, clock, calendar, chat]), [[0, 1, 3], [2]])
    }

    func testAnIndependentStepDoesNotWaitForADependentChain() {
        let plan = [picture("a red circle", true),
                    picture("make it black and white", false, edit: true),
                    picture("a blue square", true)]
        XCTAssertEqual(ChainSchedule.stages(plan), [[0, 2], [1]],
                       "das unabhängige Bild läuft neben der Kette, nicht dahinter")
        XCTAssertEqual(ChainSchedule.stages(plan, limit: 1), [[0], [1], [2]],
                       "ein lokales Modell behält die Reihenfolge des Nutzers")
    }

    func testDeletingTheHistoryCutsTheStages() {
        XCTAssertEqual(ChainSchedule.stages([chat, history, clock]), [[0], [1], [2]],
                       "hinter dem Löschen beginnt ein neuer Lauf")
        XCTAssertEqual(ChainSchedule.stages([history, chat, clock]), [[0], [1, 2]])
        XCTAssertEqual(ChainSchedule.stages([chat, calendar, clock, history, chat]),
                       [[0, 2], [1], [3], [4]],
                       "nur das Löschen beginnt einen neuen Lauf, der Termin hält die Fragen nicht auf")
    }

    func testThreeSeparatePicturesEntstehenInEinerStufe() {
        let plan = ["roter Kreis", "blaues Quadrat", "grünes Dreieck"].map { prompt in
            var decision = ToolDecision(route: .imageCreate, picturePrompt: prompt)
            decision.wish = "Male " + prompt
            decision.standalone = true
            return decision
        }
        XCTAssertEqual(ChainSchedule.stages(plan), [[0, 1, 2]])
        var edit = ToolDecision(route: .imageEdit, pictureInstruction: "heller")
        edit.standalone = true
        XCTAssertEqual(ChainSchedule.stages(plan + [edit]), [[0, 1, 2], [3]],
                       "eine Bearbeitung wartet auf die Bilder der Nachricht")
    }

    func testTheStageNeverGrowsBeyondTheLimit() {
        let five = (0..<5).map { _ in chat }
        XCTAssertEqual(ChainSchedule.stages(five, limit: 2), [[0, 1], [2, 3], [4]])
        XCTAssertEqual(ChainSchedule.stages(five, limit: 3), [[0, 1, 2], [3, 4]])
        XCTAssertEqual(ChainSchedule.stages([chat, clock], limit: 1), [[0], [1]],
                       "ein lokales Modell bekommt einen Schritt nach dem anderen")
        XCTAssertEqual(ChainSchedule.stages([chat, clock], limit: 0), [[0], [1]],
                       "kein Modell darf weniger als eine Stufe gleichzeitig rechnen")
    }

    func testAnEmptyPlanHasNoStage() {
        XCTAssertEqual(ChainSchedule.stages([]), [])
    }
}
