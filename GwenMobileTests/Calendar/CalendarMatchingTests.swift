@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class CalendarMatchingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func match(_ title: String, _ location: String = "", _ notes: String = "",
                       minutesFromNow: Int = 0) -> CalendarMatch {
        CalendarMatch(title: title, location: location, notes: notes,
                      start: now.addingTimeInterval(TimeInterval(minutesFromNow * 60)))
    }

    func testAQueryThatMatchesNothingRefusesToPickAnArbitraryAppointment() {
        let candidates = [match("Zahnarzt Meier"), match("Jahreshauptversammlung")]
        XCTAssertNil(CalendarMatching.bestIndex(in: candidates, query: "Dr. Kohn", now: now))
    }

    func testAnEmptyQueryNeverSelectsAnything() {
        let candidates = [match("Zahnarzt Meier")]
        XCTAssertNil(CalendarMatching.bestIndex(in: candidates, query: "", now: now))
        XCTAssertNil(CalendarMatching.bestIndex(in: candidates, query: "   ", now: now))
        XCTAssertNil(CalendarMatching.bestIndex(in: [], query: "Zahnarzt", now: now))
    }

    func testTheClosestAppointmentWinsAmongTheMatchedTitles() {
        let candidates = [match("Zahnarzt", minutesFromNow: 600),
                          match("Friseur", minutesFromNow: 5),
                          match("Zahnarzt", minutesFromNow: -30)]
        XCTAssertEqual(CalendarMatching.bestIndex(in: candidates, query: "Zahnarzt", now: now), 2)
    }

    func testLocationAndNotesAlsoIdentifyAnAppointment() {
        let candidates = [match("Offen", "Praxis Nord", "Zahnarzt Dr. Meier"), match("Offen", "", "")]
        XCTAssertEqual(CalendarMatching.bestIndex(in: candidates, query: "praxis nord", now: now), 0)
        XCTAssertEqual(CalendarMatching.bestIndex(in: candidates, query: "MEIER", now: now), 0)
    }

    func testAnyWordOfTheQueryIsEnoughBecauseTheModelNamesTheEventLoosely() {
        let candidates = [match("Zahnarzt Meier"), match("Mitbringparty")]
        XCTAssertEqual(CalendarMatching.bestIndex(in: candidates, query: "Kater Mitbring", now: now), 1)
    }

    func testWordsAreFoldedAndSplitOnNonAlphanumerics() {
        XCTAssertEqual(MatchScoring.words(in: "  Zahnarzt   Meier "), ["zahnarzt", "meier"])
        XCTAssertEqual(MatchScoring.words(in: "\n\t"), [])
        XCTAssertEqual(MatchScoring.words(in: "Zahnarzt?"), ["zahnarzt"])
    }

    func testPunctuationAndDiacriticsDoNotHideAMatch() {
        let candidate = match("Zahnarzt Dr. Müller")
        XCTAssertEqual(CalendarMatching.bestIndex(in: [candidate], query: "zahnarzt muller?", now: now), 0)
    }

    func testMatchNeedsAtLeastOneWordAndACarryingField() {
        XCTAssertNotEqual(MatchScoring.strength(of: match("Impftermin"), words: ["impf"]), .none)
        XCTAssertEqual(MatchScoring.strength(of: match("Impftermin"), words: []), .none)
        XCTAssertEqual(MatchScoring.strength(of: match("Impftermin"), words: ["zahnarzt"]), .none)
    }

    func testCarryingKeepsOnlyTheWordsThatCanCarryARequest() {
        XCTAssertEqual(MatchScoring.carrying(["am", "zahnarzt", "der", "um"]), ["zahnarzt"])
    }

    func testAQueryOfMereFillerWordsRefusesToPickAnything() {
        let candidates = [match("Am Abend"), match("Zahnarzt"), match("Termin um 10")]
        XCTAssertNil(CalendarMatching.bestIndex(in: candidates, query: "am", now: now))
        XCTAssertNil(CalendarMatching.bestIndex(in: candidates, query: "der um", now: now))
    }

    func testAWordFromTheTitleOutranksANearerAppointmentThatOnlyMentionsItInAPlace() {
        let candidates = [match("Erledigungen", "Zahnarzt", "", minutesFromNow: 1),
                          match("Zahnarzt", minutesFromNow: 600)]
        XCTAssertEqual(CalendarMatching.bestIndex(in: candidates, query: "Zahnarzt", now: now), 1)
    }

    func testADestructiveSearchOnlyAcceptsWhatTheTitleItselfCarries() {
        let candidates = [match("Offen", "Praxis Nord", "Zahnarzt Dr. Meier"),
                          match("Zahnarzt Meier", minutesFromNow: 600)]
        XCTAssertEqual(CalendarMatching.bestIndex(in: candidates, query: "meier", now: now), 1,
                       "ohne Löschwunsch gewinnt der Titel, sonst der nächstgelegene Treffer")
        XCTAssertEqual(CalendarMatching.bestIndex(in: Array(candidates.dropFirst()), query: "praxis nord",
                                                  now: now, requiresTitle: true), nil)
        XCTAssertEqual(CalendarMatching.bestIndex(in: candidates, query: "zahnarzt",
                                                  now: now, requiresTitle: true), 1)
    }
}
