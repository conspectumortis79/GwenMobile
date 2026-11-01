@testable import GwenMobileFeatureCore
import MapKit
import XCTest
import GwenMobileKit

final class PlaceWishOverlapTests: XCTestCase {
    private let wish = "Bitte eine Route nach Frankfurter Straße 34 Berlin"

    func testTheUsersAddressCoversMoreOfTheWishThanAnInventedOne() {
        XCTAssertEqual(PlaceWishGrounding.overlap(of: "Frankfurter Straße 34, 10115 Berlin", with: wish), 4)
        XCTAssertEqual(PlaceWishGrounding.overlap(of: "Bismarckstraße 15, 10117 Berlin", with: wish), 1)
        XCTAssertEqual(PlaceWishGrounding.overlap(of: "Teststraße 14, Beispielstadt", with: wish), 0)
    }

    func testSpellingAndAbbreviationsAreComparedWithoutAnyWordList() {
        XCTAssertEqual(PlaceWishGrounding.overlap(of: "Frankfurter Strasse 34", with: wish), 3,
                       "ß und ss sind nach Unicode-Großschreibung dasselbe")
        XCTAssertEqual(PlaceWishGrounding.overlap(of: "Frankfurter Straße 34", with: "Route zur Frankfurter Str. 34"), 3)
        XCTAssertEqual(PlaceWishGrounding.overlap(of: "Frankfurter Straße 35", with: wish), 2,
                       "eine andere Hausnummer zählt nicht")
    }
}

final class PlaceRankingTests: XCTestCase {
    func testARouteLeadsWithTheHitThatMatchesTheUsersWords() {
        let hits = [PlaceCandidate(label: "Bismarckstraße 15 Bismarckstraße 15, 10117 Berlin", metres: nil),
                    PlaceCandidate(label: "Berlin", metres: nil),
                    PlaceCandidate(label: "Frankfurter Straße 34 Frankfurter Straße 34, 10115 Berlin", metres: nil)]
        XCTAssertEqual(PlaceRanking.order(hits, wish: "Bitte eine Route nach Frankfurter Straße 34 Berlin",
                                          byDistance: false),
                       [2], "gemessen: die KI schlug Bismarckstraße und Berlin vor, Apple Karten fand die Adresse")
    }

    func testARouteKeepsCloseAlternativesAndDropsTheInventedOnes() {
        let hits = [PlaceCandidate(label: "Heidelberg", metres: nil),
                    PlaceCandidate(label: "Frankfurter Straße 34, 10115 Berlin", metres: nil),
                    PlaceCandidate(label: "Frankfurter Straße, 10115 Berlin", metres: nil),
                    PlaceCandidate(label: "Friedrich-Ebert-Straße 85, Wuppertal", metres: nil),
                    PlaceCandidate(label: "Frankfurter Straße, 64293 Darmstadt", metres: nil)]
        XCTAssertEqual(PlaceRanking.order(hits, wish: "Bitte eine Route nach Frankfurter Straße 34 Berlin",
                                          byDistance: false),
                       [1, 2], "gemessen auf dem iPhone: Heidelberg, Wuppertal und Darmstadt standen darunter")
    }

    func testARouteWithoutAnyMatchKeepsEveryHit() {
        let hits = [PlaceCandidate(label: "Hauptbahnhof", metres: nil), PlaceCandidate(label: "Bahnhofplatz", metres: nil)]
        XCTAssertEqual(PlaceRanking.order(hits, wish: "Bring mich heim", byDistance: false), [0, 1])
    }

    func testANamedChainComesBeforeCloserPlacesOfOtherNames() {
        let hits = [PlaceCandidate(label: "EDEKA Heinrich", metres: 300),
                    PlaceCandidate(label: "REWE", metres: 450),
                    PlaceCandidate(label: "Aldi Süd", metres: 200),
                    PlaceCandidate(label: "REWE City", metres: 900)]
        XCTAssertEqual(PlaceRanking.order(hits, wish: "Zeig mir den nächsten REWE-Markt", byDistance: true),
                       [1, 3, 2, 0])
    }

    func testANeedWithoutANameKeepsTheNearestFirst() {
        let hits = [PlaceCandidate(label: "Pizzeria Roma", metres: 800),
                    PlaceCandidate(label: "Imbiss am Markt", metres: 150),
                    PlaceCandidate(label: "Café", metres: nil)]
        XCTAssertEqual(PlaceRanking.order(hits, wish: "Wo kann ich hier was essen?", byDistance: true), [1, 0, 2])
    }

    func testMissingDistancesAreSortedToTheEndFromEitherSide() {
        let knownFirst = [PlaceCandidate(label: "nah", metres: 100), PlaceCandidate(label: "ohne", metres: nil)]
        XCTAssertEqual(PlaceRanking.order(knownFirst, wish: "x", byDistance: true), [0, 1])
        let unknownFirst = [PlaceCandidate(label: "ohne", metres: nil), PlaceCandidate(label: "nah", metres: 100)]
        XCTAssertEqual(PlaceRanking.order(unknownFirst, wish: "x", byDistance: true), [1, 0])
    }

    func testTheUsersOwnWordsAreAlwaysSearchedToo() {
        XCTAssertEqual(PlaceRanking.queries(terms: ["Bismarckstraße 15", "", "Berlin", "Bismarckstraße"],
                                            wish: " Bitte eine Route nach Frankfurter Straße 34 ", limit: 3),
                       ["Bismarckstraße 15", "Berlin", "Bismarckstraße", "Bitte eine Route nach Frankfurter Straße 34"])
        XCTAssertEqual(PlaceRanking.queries(terms: ["REWE"], wish: "REWE", limit: 3), ["REWE"])
        XCTAssertEqual(PlaceRanking.queries(terms: ["REWE"], wish: "", limit: 3), ["REWE"])
    }
}

@MainActor
final class PlaceSearchRankingTests: XCTestCase {
    func testTheRankedHitsAreCutAtTheLimit() {
        let hits = (1...5).map { index in
            NearbyHit(item: MKMapItem(), place: NearbyPlace(name: "REWE \(index)", latitude: nil, longitude: nil,
                                                            metres: 100 * index))
        }
        XCTAssertEqual(PlaceSearch.ranked(hits, wish: "REWE", byDistance: true).map(\.place.name),
                       ["REWE 1", "REWE 2", "REWE 3"])
    }
}

final class NearbyConfirmationTests: XCTestCase {
    private let wish = "Zeig mir den nächsten REWE-Markt"

    private static func nearby(_ terms: [String]) -> ToolDecision {
        ToolDecision(route: .nearbyPlace(terms: terms, mode: .walking))
    }

    func testOnlyTermsMadeOfTheUsersWordsCount() {
        XCTAssertTrue(PlaceWishGrounding.isGrounded("REWE", in: wish))
        XCTAssertTrue(PlaceWishGrounding.isGrounded("REWE-Markt", in: wish))
        XCTAssertFalse(PlaceWishGrounding.isGrounded("Supermarkt", in: wish))
        XCTAssertFalse(PlaceWishGrounding.isGrounded("nächster Supermarkt in meiner Nähe", in: wish),
                       "gemessen: ein einziges passendes Füllwort macht den Begriff noch nicht zum eigenen")
    }

    func testACategoryInsteadOfTheNamedChainIsAskedOnceAndTheAnswerWins() async {
        var hints: [String] = []
        var first = Self.nearby(["Supermarkt", "Lebensmittelgeschäft"])
        first.wish = wish
        let result = await PlaceWishConfirmation.checkedNearby(first, wish: wish) { hint in
            hints.append(hint)
            return Self.nearby(["REWE", "Supermarkt"])
        }
        XCTAssertEqual(hints, [PlaceWishConfirmation.hint])
        XCTAssertEqual(result.route, .nearbyPlace(terms: ["REWE", "Supermarkt"], mode: .walking))
        XCTAssertEqual(result.wish, wish)
    }

    func testAStubbornCategoryIsAskedAtMostTwiceAndThenKept() async {
        var calls = 0
        let need = Self.nearby(["Restaurant", "Imbiss"])
        let result = await PlaceWishConfirmation.checkedNearby(need, wish: "Wo kann ich hier was essen?") { _ in
            calls += 1
            return need
        }
        XCTAssertEqual(calls, PlaceWishConfirmation.attempts, "gemessen: eine Nachfrage reichte in 5 von 6 Fällen")
        XCTAssertEqual(result.route, need.route)
    }

    func testTheUsersChainAmongTheTermsIsNeverAskedAgain() async {
        var calls = 0
        let good = Self.nearby(["REWE Supermarkt", "REWE"])
        let result = await PlaceWishConfirmation.checkedNearby(good, wish: wish) { _ in
            calls += 1
            return nil
        }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(result, good)
    }

    func testAnAnswerThatIsNoNearbySearchKeepsTheFirstDecision() async {
        let first = Self.nearby(["Supermarkt"])
        let result = await PlaceWishConfirmation.checkedNearby(first, wish: wish) { _ in ToolDecision(route: .chat) }
        XCTAssertEqual(result, first)
    }

    func testRoutesAndOtherToolsAreNotAskedAgain() async {
        var calls = 0
        let route = ToolDecision(route: .routeToPlace(terms: ["Bismarckstraße 15"], mode: .automatic))
        let result = await PlaceWishConfirmation.checkedNearby(route, wish: "Route nach Frankfurter Straße 34") { _ in
            calls += 1
            return nil
        }
        XCTAssertEqual(calls, 0, "Routen findet Apple Karten über den Wunschtext selbst")
        XCTAssertEqual(result, route)
    }
}
