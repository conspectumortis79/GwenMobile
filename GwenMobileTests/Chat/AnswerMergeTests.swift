@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class AnswerMergeTests: XCTestCase {
    private let frankfurter = NearbyPlace(name: "Frankfurter Straße 34", latitude: 52.52, longitude: 13.405,
                                          metres: nil, mode: .automatic)
    private let rewe = NearbyPlace(name: "REWE", latitude: 52.51, longitude: 13.407, metres: 450)
    private let reweCenter = NearbyPlace(name: "REWE Center", latitude: 52.50, longitude: 13.409, metres: 900)

    private func source(_ domain: String) -> WebSource {
        WebSource(title: domain, url: "https://\(domain)", domain: domain)
    }

    func testARouteAndANearbySearchInOneAnswerKeepBothLinkBlocks() {
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "Route\n- Frankfurter Straße 34",
                              artifacts: AnswerArtifacts(placeGroups: PlaceGroup.single([frankfurter],
                                                                                        headingKey: "route_head"))))
        carry.add(AnswerPiece(text: "In deiner Nähe\n- REWE",
                              artifacts: AnswerArtifacts(placeGroups: PlaceGroup.single([rewe],
                                                                                        headingKey: "place_head"))))
        XCTAssertEqual(carry.artifacts.placeGroups,
                       [PlaceGroup(headingKey: "route_head", places: [frankfurter]),
                        PlaceGroup(headingKey: "place_head", places: [rewe])],
                       "die Route darf nicht vom zweiten Schritt überschrieben werden")
    }

    func testTwoNearbySearchesShareOneBlockWithoutDuplicates() {
        let first = PlaceGroup.single([rewe], headingKey: "place_head")
        let second = PlaceGroup.single([rewe, reweCenter], headingKey: "place_head")
        XCTAssertEqual(PlaceGroup.combined(first, second),
                       [PlaceGroup(headingKey: "place_head", places: [rewe, reweCenter])])
        XCTAssertNil(PlaceGroup.combined(nil, nil))
        XCTAssertNil(PlaceGroup.single([], headingKey: "route_head"))
    }

    func testFootnotesOfALaterSearchPointToItsOwnSources() {
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "Berlin liegt an der Spree [1][2].",
                              artifacts: AnswerArtifacts(sources: [source("a.de"), source("b.de")])))
        carry.add(AnswerPiece(text: "REWE öffnet um 7 Uhr [1].",
                              artifacts: AnswerArtifacts(sources: [source("rewe.de")])))
        XCTAssertEqual(carry.artifacts.sources?.map(\.domain), ["a.de", "b.de", "rewe.de"])
        XCTAssertEqual(carry.text, "Berlin liegt an der Spree [1][2].\n\nREWE öffnet um 7 Uhr [3].")
    }

    func testAPieceWithoutSourcesKeepsItsBracketsAndShiftsNothing() {
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "Laut Quelle [1].", artifacts: AnswerArtifacts(sources: [source("a.de")])))
        carry.add(AnswerPiece(text: "Das Feld data[1] bleibt."))
        XCTAssertEqual(carry.text, "Laut Quelle [1].\n\nDas Feld data[1] bleibt.")
    }

    func testSeveralChatPiecesCarryTheirWishAsAHeading() {
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "Antwort A", step: 0))
        carry.add(AnswerPiece(text: "Antwort B", step: 1))
        XCTAssertEqual(carry.text(withHeadings: [0: "Frage A", 1: "Frage B"]),
                       "Frage A\n\nAntwort A\n\nFrage B\n\nAntwort B")
    }

    func testFileReferencesOfSeveralStepsAreCollectedOnce() {
        let plan = FileRef(name: "plan.pdf")
        let table = FileRef(name: "tabelle.xlsx")
        let merged = AnswerArtifacts(fileRefs: [plan]).merged(with: AnswerArtifacts(fileRefs: [plan, table]))
        XCTAssertEqual(merged.fileRefs, [plan, table])
    }

    func testTheSourceReviewTravelsWithTheArtifacts() {
        let review = SourceReview(sourceDomains: 2, citedClaims: 1, verified: true)
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "Antwort [1].",
                              artifacts: AnswerArtifacts(sources: [source("a.de")], sourceReview: review)))
        XCTAssertEqual(carry.artifacts.sourceReview, review)
    }

    func testTheSourceReviewOfALaterPiecePointsToItsShiftedSources() {
        var review = SourceReview(sourceGroups: [[0, 2], [1]], citedClaims: 1, verified: true)
        review.results = [SourceReview.ClaimResult(claim: "Der Turm ist 330 m hoch", verdict: .contradicted,
                                                   sources: [1, 3, 7], contradicts: [2])]
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "Bilder vom Eiffelturm",
                              artifacts: AnswerArtifacts(sources: [source("bild1.de"), source("bild2.de")])))
        carry.add(AnswerPiece(text: "Der Turm ist 330 m hoch [1][3].",
                              artifacts: AnswerArtifacts(sources: [source("a.de"), source("b.de"), source("c.de")],
                                                         sourceReview: review)))
        let merged = carry.artifacts.sourceReview
        XCTAssertEqual(merged?.results.first?.sources, [3, 5, 7])
        XCTAssertEqual(merged?.results.first?.contradicts, [4])
        XCTAssertEqual(merged?.sourceGroups, [[2, 4], [3]])
        XCTAssertEqual(carry.text, "Bilder vom Eiffelturm\n\nDer Turm ist 330 m hoch [3][5].")
        XCTAssertEqual(review.shifted(by: 0, sources: 3), review)
        XCTAssertEqual(review.shifted(by: 2, sources: 0), review)
    }

    func testTheSourceReviewSurvivesAStoreRoundtrip() throws {
        var message = ChatMessage(role: .assistant, text: "Antwort [1]",
                                  sources: [Fixtures.source("T", "https://a.test", "a.test")])
        message.sourceReview = SourceReview(sourceDomains: 1, citedClaims: 1,
                                            checkedClaims: 1, verified: true)
        let data = try JSONEncoder().encode([message])
        let decoded = try JSONDecoder().decode([ChatMessage].self, from: data)
        XCTAssertEqual(decoded.first?.sourceReview, message.sourceReview)
    }
}

final class CitationShiftTests: XCTestCase {
    func testOnlyMarkersOfTheOwnSourcesAreShifted() {
        XCTAssertEqual(CitationMarkers.shifted("A [1] B [2] C [3] D [0]", by: 4, sources: 2),
                       "A [5] B [6] C [3] D [0]")
    }

    func testNothingChangesWithoutEarlierSources() {
        XCTAssertEqual(CitationMarkers.shifted("A [1]", by: 0, sources: 1), "A [1]")
        XCTAssertEqual(CitationMarkers.shifted("A [1]", by: 3, sources: 0), "A [1]")
    }

    func testNonASCIIDigitsAreNotCitationMarkers() {
        XCTAssertEqual(CitationMarkers.shifted("A [١] B [2]", by: 1, sources: 2), "A [١] B [3]")
        XCTAssertEqual(SourceReview.citationNumbers(in: "A [١] B [2]"), [2])
        XCTAssertEqual(SourceReview.citationNumbers(in: "A [١]"), [])
    }

    func testGroupedMarkersShiftTheirOwnNumbers() {
        XCTAssertEqual(CitationMarkers.shifted("A [1, 3] B [2; 4]", by: 4, sources: 3),
                       "A [5, 7] B [6; 4]")
        XCTAssertEqual(SourceReview.citationNumbers(in: "A [1, 3, 4] B [2]"), [1, 3, 4, 2])
    }
}

extension AnswerMergeTests {
    func testCitationPiecesKeepTextAfterTheLastNumber() {
        let pieces = CitationMarkers.pieces(of: "12 und 3 x")
        XCTAssertEqual(pieces.map(\.text), ["12", " und ", "3", " x"])
        XCTAssertEqual(pieces.compactMap(\.number), [12, 3])
    }
}

extension AnswerMergeTests {
    func testApplyingAnAnswerTakesEveryAnswerFieldAndKeepsTheQuestionSide() {
        let keptID = UUID()
        let keptDate = Date(timeIntervalSince1970: 1_700_000_000)
        let keptOffer = ScanReminderOffer(title: "alt", due: nil)
        let keptScan = AttachedFile(file: "doc_scan.pdf", name: "scan.pdf", kind: .pdf, bytes: 10)
        var base = ChatMessage(role: .user, text: "Frage")
        base.id = keptID
        base.date = keptDate
        base.images = [Attachment(file: "eingang.jpg")]
        base.ocrFiles = [OcrFile(file: "ocr/eingang.jpg.txt", chars: 4)]
        base.reminderOffer = keptOffer
        base.scanRef = keptScan

        var fresh = ChatMessage(role: .assistant, text: "Antwort")
        fresh.model = "model-x"
        fresh.elapsed = 1.5
        fresh.outImages = [Attachment(file: "ausgang.jpg")]
        fresh.sources = [WebSource(title: "Quelle", url: "https://example.test", domain: "example.test")]
        fresh.sourcesHeadingKey = "research_head"
        fresh.sourceReview = SourceReview(citedClaims: 1)
        fresh.thinking = .high
        fresh.placeGroups = [PlaceGroup(headingKey: "place_head", places: [])]
        fresh.files = [AttachedFile(file: "doc_a.txt", name: "a.txt", kind: .text, bytes: 2)]
        fresh.ocrFiles = [OcrFile(file: "ocr/neu.txt", chars: 3)]
        fresh.fileRefs = [FileRef(name: "a.txt")]
        fresh.fileRefsHeadingKey = "file_head"
        fresh.gallery = PictureGallery(query: "q", pictures: [], shown: 0)
        fresh.calendarRef = CalendarRef(eventID: "event", title: "Termin", start: Date())
        fresh.reminderRef = ReminderRef(reminderID: "reminder", title: "Aufgabe", list: "Liste",
                                        due: nil, allDay: false, place: nil)
        fresh.reminderOffer = ScanReminderOffer(title: "neu", due: nil)
        fresh.scanRef = AttachedFile(file: "doc_neu.pdf", name: "neu.pdf", kind: .pdf, bytes: 11)
        fresh.memoryRefs = [MemoryRef(entry: MemoryEntry(text: "mag Tee", category: .likes))]
        fresh.weatherRef = WeatherRef(place: "Berlin", latitude: 52.5, longitude: 13.4,
                                      day: "2026-11-03", timezone: "Europe/Berlin", hours: [])
        fresh.priceWatchRef = PriceWatchRef(watch: PriceWatch(terms: ["PS5"], goal: 400))
        fresh.dayBriefingRef = DayBriefingRef(date: "2026-11-03", greetingKey: "brief_greet_morning")
        base.applyAnswer(from: fresh)

        XCTAssertEqual(base.id, keptID)
        XCTAssertEqual(base.role, .user)
        XCTAssertEqual(base.date, keptDate)
        XCTAssertEqual(base.images, [Attachment(file: "eingang.jpg")])
        XCTAssertEqual(base.ocrFiles, [OcrFile(file: "ocr/eingang.jpg.txt", chars: 4)])
        XCTAssertEqual(base.reminderOffer, keptOffer)
        XCTAssertEqual(base.scanRef, keptScan)
        XCTAssertEqual(base.text, fresh.text)
        XCTAssertEqual(base.model, "model-x")
        XCTAssertEqual(base.elapsed, 1.5)
        XCTAssertEqual(base.outImages, fresh.outImages)
        XCTAssertEqual(base.sources, fresh.sources)
        XCTAssertEqual(base.sourcesHeadingKey, "research_head")
        XCTAssertEqual(base.sourceReview, fresh.sourceReview)
        XCTAssertEqual(base.thinking, .high)
        XCTAssertEqual(base.placeGroups, fresh.placeGroups)
        XCTAssertEqual(base.files, fresh.files)
        XCTAssertEqual(base.fileRefs, fresh.fileRefs)
        XCTAssertEqual(base.fileRefsHeadingKey, "file_head")
        XCTAssertEqual(base.gallery, fresh.gallery)
        XCTAssertEqual(base.calendarRef, fresh.calendarRef)
        XCTAssertEqual(base.reminderRef, fresh.reminderRef)
        XCTAssertEqual(base.memoryRefs, fresh.memoryRefs)
        XCTAssertEqual(base.weatherRef, fresh.weatherRef)
        XCTAssertEqual(base.priceWatchRef, fresh.priceWatchRef)
        XCTAssertEqual(base.dayBriefingRef, fresh.dayBriefingRef)
    }

    func testVideoFilesFromTwoStepsStayInTheMergedAnswer() {
        let first = AttachedFile(file: "doc_a.mp4", name: "a.mp4", kind: .video, bytes: 12)
        let second = AttachedFile(file: "doc_b.mp4", name: "b.mp4", kind: .video, bytes: 24)
        let merged = AnswerArtifacts(files: [first]).merged(with: AnswerArtifacts(files: [second]))
        XCTAssertEqual(merged.files, [first, second])
    }
}
