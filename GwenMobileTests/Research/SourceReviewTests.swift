@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SourceReviewTests: GwenTestCase {
    private func hit(_ domain: String) -> WebHit {
        Fixtures.hit("T", "https://\(domain)/a", domain, "Text")
    }

    private func decoded(_ json: String) throws -> (SourceReview, DecodeIssues) {
        let issues = DecodeIssues()
        let decoder = JSONDecoder()
        decoder.userInfo[try XCTUnwrap(DecodeIssues.userInfoKey)] = issues
        return (try decoder.decode(SourceReview.self, from: Data(json.utf8)), issues)
    }

    func testAnOldReviewTakesItsOriginsFromTheCitedDomains() throws {
        let (review, issues) = try decoded(#"{"citedDomains":2}"#)
        XCTAssertEqual(review.citedOrigins, 2)
        XCTAssertTrue(review.crossChecked)
        XCTAssertFalse(issues.isDamaged)
    }

    func testADamagedOldDomainCountIsReported() throws {
        let (review, issues) = try decoded(#"{"citedDomains":"zwei"}"#)
        XCTAssertEqual(review.citedOrigins, 0)
        XCTAssertEqual(issues.damagedFields, "citedDomains")
    }

    func testTwoSentencesFromTwoDomainsCountAsCrossChecked() {
        let answer = "Berlin liegt an der Spree [1]. Die Einwohnerzahl wächst [2]."
        let review = SourceReview.analyze(answer: answer, hits: [hit("a.test"), hit("b.test")])
        XCTAssertEqual(review.citedClaims, 2)
        XCTAssertEqual(review.sourceDomains, 2)
        XCTAssertTrue(review.crossChecked)
        XCTAssertFalse(review.singleSource)
    }

    func testAClaimWithTwoSourcesInOneSentenceIsCrossChecked() {
        let review = SourceReview.analyze(answer: "Berlin liegt an der Spree [1][2].",
                                          hits: [hit("a.test"), hit("b.test")])
        XCTAssertEqual(review.citedClaims, 1)
        XCTAssertTrue(review.crossChecked)
    }

    func testTwoSentencesFromOneDomainStayASingleSource() {
        let answer = "Berlin liegt an der Spree [1]. Die Einwohnerzahl wächst [2]."
        let review = SourceReview.analyze(answer: answer, hits: [hit("a.test"), hit("www.a.test")])
        XCTAssertTrue(review.singleSource)
    }

    func testAListItemIsOneClaim() {
        let answer = "- **Theater**: 242 Millionen Euro [1]\n- **Tegut**: 12 Millionen [2]"
        let review = SourceReview.analyze(answer: answer, hits: [hit("a.test"), hit("b.test")])
        XCTAssertEqual(review.citedClaims, 2)
        XCTAssertTrue(review.crossChecked)
    }

    func testAnAnswerWithoutMarkersHasNoCitedClaims() {
        let review = SourceReview.analyze(answer: "Berlin liegt an der Spree.", hits: [hit("a.test")])
        XCTAssertEqual(review.citedClaims, 0)
        XCTAssertFalse(review.singleSource)
        XCTAssertEqual(review.sourceDomains, 1)
    }

    func testANumberWithoutASourceIsIgnored() {
        let review = SourceReview.analyze(answer: "Eine Zahl [7].", hits: [hit("a.test")])
        XCTAssertEqual(review.citedClaims, 0)
    }

    func testTheCoverageNoteNamesTheOnlyWebsite() {
        let note = SourceReview.coverageNote(hits: [hit("news.test"), hit("www.news.test")])
        XCTAssertTrue(note.contains("news.test"), note)
        XCTAssertTrue(SourceReview.coverageNote(hits: [hit("a.test"), hit("b.test")]).isEmpty)
    }

    func testTheVerifierMarksUnsupportedClaims() {
        let review = SourceReview(citedClaims: 1)
        let updated = review.applying([
            SourceReview.Claim(claim: "Berlin liegt an der Spree", sources: [1], supported: true),
            SourceReview.Claim(claim: "Berlin hat 9 Millionen Einwohner", sources: [1], supported: false),
            SourceReview.Claim(claim: "ohne Urteil", sources: [1], supported: nil),
        ])
        XCTAssertTrue(updated.verified)
        XCTAssertEqual(updated.checkedClaims, 2)
        XCTAssertEqual(updated.unsupported, ["Berlin hat 9 Millionen Einwohner"])
    }

    func testAnEmptyVerdictLeavesTheReviewUnverified() {
        let review = SourceReview(citedClaims: 1)
        XCTAssertFalse(review.applying([]).verified)
    }

    func testTheVerifierMarksContradictions() {
        let review = SourceReview(citedClaims: 1)
        let updated = review.applying([
            SourceReview.Claim(claim: "Nur Neubauten", sources: [1], verdict: .contradicted, contradicts: [3]),
            SourceReview.Claim(claim: "Rückwirkend ab Januar", sources: [4], verdict: .unsupported),
            SourceReview.Claim(claim: "Gesetz beschlossen", sources: [1, 2], verdict: .supported),
        ])
        XCTAssertTrue(updated.verified)
        XCTAssertEqual(updated.checkedClaims, 3)
        XCTAssertEqual(updated.contradicted, ["Nur Neubauten"])
        XCTAssertEqual(updated.unsupported, ["Rückwirkend ab Januar"])
        XCTAssertEqual(updated.results.count, 3)
        XCTAssertEqual(updated.results[0].contradicts, [3])
    }

    func testParsingReadsTheVerdictAndContradictions() {
        let raw = #"{"claims":[{"claim":"Nur Neubauten","sources":[1],"verdict":"contradicted","contradicts":[3]}]}"#
        XCTAssertEqual(SourceVerifier.parse(raw)?.first?.verdict, .contradicted)
        XCTAssertEqual(SourceVerifier.parse(raw)?.first?.contradicts, [3])
    }

    func testTheReportKeepsOnlyWarningClaims() {
        let review = SourceReview(citedClaims: 1)
        let updated = review.applying([
            SourceReview.Claim(claim: "Belegt", sources: [1], verdict: .supported),
            SourceReview.Claim(claim: "Nicht belegt", sources: [1], verdict: .unsupported),
            SourceReview.Claim(claim: "Widersprochen", sources: [1], verdict: .contradicted),
        ])
        XCTAssertEqual(updated.results.count, 3)
        XCTAssertEqual(updated.warnings.map(\.claim), ["Nicht belegt", "Widersprochen"])
    }

    func testAnUnknownVerdictIsSkippedInsteadOfBlockingTheWholeCheck() {
        let raw = #"{"claims":[{"claim":"Unklar","sources":[1],"verdict":"teilweise"}]}"#
        let parsed = SourceVerifier.parse(raw)
        XCTAssertEqual(parsed?.first?.verdict, .unknown)
        XCTAssertNil(parsed?.first?.resolvedVerdict)
        XCTAssertFalse(SourceReview(citedClaims: 1).applying(parsed ?? []).verified)
    }

    func testAnUnsupportedClaimWithoutSourceNumbersIsStillReported() {
        let updated = SourceReview(citedClaims: 1).applying([
            SourceReview.Claim(claim: "Nur behauptet", sources: [], verdict: .unsupported),
        ])
        XCTAssertTrue(updated.verified)
        XCTAssertEqual(updated.unsupported, ["Nur behauptet"])
        XCTAssertEqual(updated.results.first?.sources, [])
    }

    func testASupportedClaimWithoutSourceNumbersIsIgnored() {
        let updated = SourceReview(citedClaims: 1).applying([
            SourceReview.Claim(claim: "Ohne Beleg", sources: [], verdict: .supported),
        ])
        XCTAssertFalse(updated.verified)
        XCTAssertTrue(updated.results.isEmpty)
    }

    func testVerificationMissingOnlyWhileCitationsAreUnchecked() {
        XCTAssertTrue(SourceReview(citedClaims: 3).verificationMissing)
        XCTAssertFalse(SourceReview(citedClaims: 0).verificationMissing)
        let checked = SourceReview(citedClaims: 1)
            .applying([SourceReview.Claim(claim: "Belegt", sources: [1], verdict: .supported)])
        XCTAssertFalse(checked.verificationMissing)
    }

    func testTheVerifierRetriesAnUnreadableReply() async {
        let review = SourceReview(citedClaims: 1)
        let calls = LockedValue(0)
        var verifier = SourceVerifier(baseURL: "https://example.test/v1", key: "k", model: "m",
                                      thinking: .nothing)
        verifier.ask = { _ in
            let attempt = calls.mutate { stored -> Int in
                stored += 1
                return stored
            }
            return attempt == 1
                ? "not json"
                : #"{"claims":[{"claim":"Belegt","sources":[1],"verdict":"supported"}]}"#
        }
        let updated = await verifier.apply(to: review, answer: "Belegt [1].", hits: [hit("a.test")])
        XCTAssertTrue(updated.verified)
        XCTAssertEqual(calls.current, 2)
    }

    func testParsingAcceptsFencesAndRejectsGarbage() {
        let raw = "```json\n{\"claims\":[{\"claim\":\"x\",\"sources\":[1],\"supported\":false}]}\n```"
        XCTAssertEqual(SourceVerifier.parse(raw)?.first?.supported, false)
        XCTAssertNil(SourceVerifier.parse("no json at all"))
        XCTAssertEqual(SourceVerifier.parse(#"{"claims":[]}"#)?.count, 0)
    }

    func testTheVerifierContextCarriesOnlyCitedSources() {
        let hits = [hit("a.test"), hit("b.test"), hit("c.test")]
        let context = SourceVerifier.userContext(answer: "Nur eine Aussage [2].", hits: hits)
        XCTAssertTrue(context.contains("## SOURCE [2]"), context)
        XCTAssertFalse(context.contains("## SOURCE [1]"), context)
        XCTAssertFalse(context.contains("## SOURCE [3]"), context)
    }

    private func reviewed(_ claims: [SourceReview.Claim]) -> SourceReview {
        SourceReview(citedClaims: claims.count).applying(claims)
    }

    func testAMarkCoversTheStatementInTheAnswer() {
        let answer = "Berlin liegt an der Spree [1]. Berlin hat 9 Millionen Einwohner [2]."
        let review = reviewed([
            SourceReview.Claim(claim: "Berlin liegt an der Spree", sources: [1], verdict: .supported),
            SourceReview.Claim(claim: "Berlin hat 9 Millionen Einwohner", sources: [2], verdict: .unsupported),
        ])
        let marks = review.marks(in: answer)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks.first?.verdict, .unsupported)
        XCTAssertEqual(marks.first?.resultIndex, 1)
        XCTAssertEqual(marks.first.map { String(answer[$0.range]) },
                       "Berlin hat 9 Millionen Einwohner [2].")
    }

    func testBackedStatementsLeaveTheAnswerUnmarked() {
        let answer = "Berlin liegt an der Spree [1]."
        let review = reviewed([SourceReview.Claim(claim: "Berlin liegt an der Spree", sources: [1],
                                                  verdict: .supported)])
        XCTAssertTrue(review.marks(in: answer).isEmpty)
    }

    func testEveryWarningMarksItsOwnSentence() {
        let answer = "Nur Neubauten sind betroffen [1]. Rückwirkend ab Januar gilt es [2]."
        let review = reviewed([
            SourceReview.Claim(claim: "Nur Neubauten sind betroffen", sources: [1], verdict: .contradicted),
            SourceReview.Claim(claim: "Rückwirkend ab Januar gilt es", sources: [2], verdict: .unsupported),
        ])
        let marks = review.marks(in: answer)
        XCTAssertEqual(marks.map(\.verdict), [.contradicted, .unsupported])
        XCTAssertEqual(marks.map(\.resultIndex), [0, 1])
        XCTAssertEqual(marks.map { String(answer[$0.range]) },
                       ["Nur Neubauten sind betroffen [1].", "Rückwirkend ab Januar gilt es [2]."])
    }

    func testAParaphrasedClaimStillFindsItsStatement() {
        let answer = "Die Hauptstadt Berlin hat rund 9 Millionen Einwohner [1]."
        let review = reviewed([SourceReview.Claim(claim: "Berlin 9 Millionen Einwohner", sources: [1],
                                                  verdict: .unsupported)])
        XCTAssertEqual(review.marks(in: answer).count, 1)
    }

    func testAStatementTheCheckerCannotFindStaysUnmarked() {
        let answer = "Berlin liegt an der Spree [1]."
        let review = reviewed([SourceReview.Claim(claim: "Die Erde ist eine Scheibe", sources: [1],
                                                  verdict: .unsupported)])
        XCTAssertTrue(review.marks(in: answer).isEmpty)
    }

    func testAListItemIsMarkedAsAWhole() {
        let answer = "- **Theater**: 242 Millionen Euro [1]\n- **Tegut**: 12 Millionen [2]"
        let review = reviewed([SourceReview.Claim(claim: "Theater: 242 Millionen Euro", sources: [1],
                                                  verdict: .unsupported)])
        let marks = review.marks(in: answer)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks.first.map { String(answer[$0.range]) },
                       "- **Theater**: 242 Millionen Euro [1]")
    }

    func testTwoWarningsMatchTwoStatementsWithTheSameSource() {
        let answer = "Die Zahl wächst [1]. Die Zahl sinkt [1]."
        let review = reviewed([
            SourceReview.Claim(claim: "Die Zahl sinkt", sources: [1], verdict: .contradicted),
            SourceReview.Claim(claim: "Die Zahl wächst", sources: [1], verdict: .unsupported),
        ])
        let marks = review.marks(in: answer)
        XCTAssertEqual(marks.map { String(answer[$0.range]) },
                       ["Die Zahl wächst [1].", "Die Zahl sinkt [1]."])
        XCTAssertEqual(marks.map(\.verdict), [.unsupported, .contradicted])
    }

    func testASimilarButDifferentStatementStaysUnmarked() {
        let answer = "Die Zahl bleibt stabil [1]."
        let review = reviewed([SourceReview.Claim(claim: "Die Zahl sinkt", sources: [1],
                                                  verdict: .contradicted)])
        XCTAssertTrue(review.marks(in: answer).isEmpty)
    }

    func testVerdictsKeepUnsupportedClaimsEvenWithoutSourceNumbers() {
        let review = SourceReview(citedClaims: 1)
        let updated = review.applying([
            SourceReview.Claim(claim: "Zu „Beispielstadt“ findet sich in keiner Quelle etwas",
                               sources: [], verdict: .unsupported),
            SourceReview.Claim(claim: "Berlin liegt an der Spree", sources: [1], verdict: .supported),
        ])
        XCTAssertEqual(updated.checkedClaims, 2)
        XCTAssertEqual(updated.unsupported, ["Zu „Beispielstadt“ findet sich in keiner Quelle etwas"])
        XCTAssertEqual(updated.results.map(\.claim),
                       ["Zu „Beispielstadt“ findet sich in keiner Quelle etwas", "Berlin liegt an der Spree"])
    }

    func testTheVerifierPromptRulesCitedAndAbsenceStatements() {
        let prompt = PromptLibrary.text("research_verify")
        XCTAssertTrue(prompt.contains("without a source number"), prompt)
        XCTAssertTrue(prompt.contains("really lacks that detail"), prompt)
    }

    func testInsideAListItemOnlyTheWarnedSentenceIsMarked() {
        let answer = "- Aus Musterstadt: Stadtlauf am Sonntag, 11. Mai 2026 [1]; neuer Platz im Ort [1]. "
            + "Quelle [1] nennt kein Datum."
        let review = reviewed([SourceReview.Claim(claim: "Quelle [1] nennt kein Datum.", sources: [1],
                                                  verdict: .unsupported)])
        let marks = review.marks(in: answer)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks.first.map { String(answer[$0.range]) }, "Quelle [1] nennt kein Datum.")
    }

    func testAnOrdinalDateStaysInsideItsSentence() {
        let answer = "- Aus Musterstadt: Stadtlauf am Sonntag, 11. Mai 2026 [1]. Quelle [1] nennt kein Datum."
        let review = reviewed([SourceReview.Claim(claim: "Stadtlauf am Sonntag, 11. Mai 2026",
                                                  sources: [1], verdict: .unsupported)])
        let marks = review.marks(in: answer)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks.first.map { String(answer[$0.range]) },
                       "- Aus Musterstadt: Stadtlauf am Sonntag, 11. Mai 2026 [1].")
    }

    func testAParaphraseAcrossSentencesKeepsTheWholeListItem() {
        let answer = "- Aus Musterstadt: Stadtlauf am Sonntag, 11. Mai 2026 [1]. Quelle [1] nennt kein Datum."
        let review = reviewed([SourceReview.Claim(claim: "Stadtlauf am Sonntag und Quelle nennt kein Datum",
                                                  sources: [1], verdict: .contradicted)])
        let marks = review.marks(in: answer)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks.first.map { String(answer[$0.range]) }, answer)
    }
}

@MainActor
extension SourceReviewTests {
    func testTheVerifierDiscardsClaimsWithoutSourceOrVerdict() async {
        let review = SourceReview(citedClaims: 2)
        var verifier = SourceVerifier(baseURL: "https://example.test/v1", key: "k", model: "m",
                                      thinking: .nothing)
        verifier.ask = { _ in
            #"{"claims":[{"claim":"Ohne Quelle","verdict":"supported"},{"claim":"Ohne Urteil","sources":[1]}]}"#
        }
        let updated = await verifier.apply(to: review, answer: "Belegt [1].", hits: [hit("a.test")])
        XCTAssertFalse(updated.verified)
        XCTAssertEqual(updated, review)
    }
}
