@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SourceSimilarityTests: GwenTestCase {
    private let agency = "Der Bundestag hat am Mittwoch ein Gesetz beschlossen, das neue Gasheizungen ab 2027 "
        + "verbietet. Die Regelung gilt für Neubauten und sieht Übergangsfristen vor. Die Opposition kritisierte "
        + "den Zeitplan als zu knapp."
    private let other = "Die Stadtwerke melden einen neuen Rekord bei der Solarstromerzeugung. Im dritten Quartal "
        + "stieg die Einspeisung deutlich. Ein Sprecher nannte die Zahlen erfreulich und kündigte weitere Anlagen an."

    private func hit(_ id: Int, _ text: String) -> WebHit {
        WebHit(title: "T\(id)", url: "https://s\(id).test/a", domain: "s\(id).test", text: text)
    }

    func testIdenticalAgencyTextsCountAsOneOrigin() {
        let hits = [hit(1, agency), hit(2, agency), hit(3, other)]
        let groups = SourceSimilarity.clusters(hits)
        XCTAssertEqual(groups, [[0, 1], [2]])
        XCTAssertEqual(SourceSimilarity.originNumber(of: 1, groups: groups), 1)
        XCTAssertNil(SourceSimilarity.originNumber(of: 0, groups: groups))
        XCTAssertNil(SourceSimilarity.originNumber(of: 2, groups: groups))
    }

    func testDifferentTextsStaySeparate() {
        XCTAssertLessThan(SourceSimilarity.similarity(agency, other),
                          SourceSimilarity.duplicateThreshold)
        XCTAssertEqual(SourceSimilarity.clusters([hit(1, agency), hit(2, other)]), [[0], [1]])
    }

    func testSlightlyEditedCopiesStillMatch() {
        let extended = agency + " Ein Sprecher sagte, die Details würden noch geprüft."
        XCTAssertGreaterThanOrEqual(SourceSimilarity.similarity(agency, extended),
                                    SourceSimilarity.duplicateThreshold)
        XCTAssertEqual(SourceSimilarity.clusters([hit(1, agency), hit(2, extended)]), [[0, 1]])
    }

    func testShortTextsAreNeverCalledCopies() {
        XCTAssertEqual(SourceSimilarity.similarity("Text", "Text"), 0)
        XCTAssertEqual(SourceSimilarity.clusters([hit(1, "Text"), hit(2, "Text")]), [[0], [1]])
    }

    func testAnAnswerOnOneOriginIsASingleSource() {
        let hits = [hit(1, agency), hit(2, agency)]
        let review = SourceReview.analyze(answer: "Der Bundestag hat das Gesetz beschlossen [1][2].", hits: hits)
        XCTAssertEqual(review.citedSources, 2)
        XCTAssertEqual(review.citedOrigins, 1)
        XCTAssertEqual(review.citedDuplicates, 1)
        XCTAssertTrue(review.singleSource)
        XCTAssertFalse(review.crossChecked)
        XCTAssertEqual(review.copyCount, 1)
    }

    func testCopiedSourcesDoNotCountAsIndependentConfirmations() {
        let hits = [hit(1, agency), hit(2, agency), hit(3, other)]
        let answer = "Der Bundestag hat das Gesetz beschlossen [1]. Die Stadtwerke melden einen Rekord [2][3]."
        let review = SourceReview.analyze(answer: answer, hits: hits)
        XCTAssertEqual(review.citedSources, 3)
        XCTAssertEqual(review.citedOrigins, 2)
        XCTAssertTrue(review.crossChecked)
        XCTAssertEqual(review.citedDuplicates, 1)
    }

    func testPagesOfOneWebsiteCountAsOnePublisher() {
        let first = WebHit(title: "A", url: "https://s1.test/a", domain: "s1.test", text: agency)
        let second = WebHit(title: "B", url: "https://s1.test/b", domain: "s1.test", text: other)
        let review = SourceReview.analyze(answer: "Beides steht dort [1][2].", hits: [first, second])
        XCTAssertEqual(review.citedOrigins, 1)
        XCTAssertTrue(review.singleSource)
    }

    func testTheCoverageNoteNamesTheSingleOrigin() {
        let note = SourceReview.coverageNote(hits: [hit(1, agency), hit(2, agency)])
        XCTAssertTrue(note.contains("one origin"), note)
    }
}
