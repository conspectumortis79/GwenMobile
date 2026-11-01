@testable import GwenMobileSystem
@testable import GwenMobileFeatureCore
import Foundation
import XCTest
import GwenMobileKit

final class ResearchGapCoverageTests: GwenTestCase {
    override func tearDown() {
        MockHTTP.uninstall()
        super.tearDown()
    }

    func testTheAnswerLengthTraceLine() {
        XCTAssertTrue(AnswerLength.compact.traceLine.contains("länge=150"))
        XCTAssertTrue(AnswerLength.detailed(items: 3).traceLine.contains("punkte=3"))
    }

    func testTheSourceGuardRiskTable() {
        XCTAssertEqual(SourceGuard.Verdict().merging(SourceGuard.Verdict()).risk, .clear)
        XCTAssertEqual(SourceGuard.Verdict(risk: .caution).merging(SourceGuard.Verdict()).risk, .caution)
        XCTAssertEqual(SourceGuard.Verdict().merging(SourceGuard.Verdict(risk: .blocked)).risk, .blocked)
        let unsafe = SourceGuard.assess(URL(string: "file:///tmp/x")!, reported: false)
        XCTAssertTrue(unsafe.reasons.contains(.unsafeAddress))
        let ipv6 = SourceGuard.assess(URL(string: "https://[::1]/x")!, reported: false)
        XCTAssertTrue(ipv6.reasons.contains(.ipAddress))
        let high = SourceGuard.assess(URL(string: "https://999.999.999.999/x")!, reported: false)
        XCTAssertFalse(high.reasons.contains(.ipAddress))
        let overflow = SourceGuard.assess(URL(string: "https://12345678901234567890.1.1.1/x")!, reported: false)
        XCTAssertFalse(overflow.reasons.contains(.ipAddress))
        XCTAssertTrue(SourceGuard.assess(nil, reported: false).reasons.contains(.unsafeAddress))
        let reported = SourceGuard.assess(URL(string: "https://seriös.test/x")!, reported: true)
        XCTAssertTrue(reported.isBlocked)
        let puny = SourceGuard.assess(URL(string: "https://xn--bcher-kva.test/x")!, reported: false)
        XCTAssertTrue(puny.reasons.contains(.punycode))
        let plain = SourceGuard.assess(URL(string: "http://seite.test/x")!, reported: false)
        XCTAssertTrue(plain.reasons.contains(.unencrypted))
    }

    func testTheMetadataNamesAuthorImprintAndPaidLinks() {
        let html = """
        <meta name="author" content="Max Mustermann">
        <a href="/impressum">Impressum</a>
        <a rel="sponsored" href="https://shop.test/x">Anzeige</a>
        """
        let metadata = SourceMetadata.from(html: html)
        XCTAssertEqual(metadata.author, "Max Mustermann")
        XCTAssertTrue(metadata.imprint)
        XCTAssertTrue(metadata.paidLinks)
        let dossier = metadata.dossier(risk: SourceGuard.Verdict())
        XCTAssertTrue(dossier.contains("author Max Mustermann"), dossier)
        XCTAssertTrue(dossier.contains("imprint found"), dossier)
        XCTAssertTrue(dossier.contains("paid links"), dossier)
    }

    func testTheMetadataStopsAfterEnoughKinds() {
        let types = (0..<8).map { "\"Type\(Character(UnicodeScalar(65 + $0)!))\"" }.joined(separator: ",")
        let html = #"<script type="application/ld+json">{"@graph":[{"@type":[\#(types)]}]}</script>"#
        XCTAssertEqual(SourceMetadata.from(html: html).kinds.count, SourceMetadata.kindLimit)
        let list = #"<script type="application/ld+json">[{"@type":"NewsArticle"}]</script>"#
        XCTAssertEqual(SourceMetadata.from(html: list).kinds, ["NewsArticle"])
        let numeric = #"<script type="application/ld+json">{"@type":123}</script>"#
        XCTAssertEqual(SourceMetadata.from(html: numeric).kinds, [])
    }

    func testTheMetadataShortensOnlyIsoDates() {
        let short = #"<script type="application/ld+json">{"@type":"NewsArticle","datePublished":"2026"}</script>"#
        XCTAssertEqual(SourceMetadata.from(html: short).published, "2026")
    }

    func testThePreviewPageIdentifiesItselfByURL() {
        let url = URL(string: "https://seite.test/code.html")!
        let page = CodePreviewPage(url: url)
        XCTAssertEqual(page.id, url)
        XCTAssertEqual(page.name, "code.html")
    }

    func testTheSearchSkipsBlockedAndInvalidHits() async throws {
        let reported = "evil-gap.test"
        SourceReports.shared.report(reported)
        defer { SourceReports.shared.withdraw(reported) }
        var rows = "<a class=\"result__a\" href=\"https://\(reported)/x\">Boese Seite hier</a>"
        rows += "<a class=\"result__a\" href=\"javascript:alert(1)\">Skript Seite hier</a>"
        for index in 1...11 {
            rows += "<a class=\"result__a\" href=\"https://site\(index).test/page\">Gute Seite \(index) hier</a>"
        }
        let rowsHTML = rows
        MockHTTP.install { _ in (200, Data(rowsHTML.utf8)) }
        let urls = try await WebSearch.searchURLs("katzen", region: nil)
        XCTAssertFalse(urls.contains { $0.host?.contains(reported) ?? false })
        XCTAssertLessThanOrEqual(urls.count, WebSearch.resultLimit)
        let again = try await WebSearch.search("katzen")
        XCTAssertEqual(again, urls)
    }

    func testTheSearchWithoutResultsFails() async {
        MockHTTP.install { _ in (200, Data("<html></html>".utf8)) }
        do {
            _ = try await WebSearch.search("katzen")
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testTheFetchedPageFallsBackToThePathNameAndRejectsShortText() async throws {
        let body = "<p>" + String(repeating: "langer Text ", count: 40) + "</p>"
        MockHTTP.install { _ in (200, Data(body.utf8)) }
        let hit = try await WebSearch.fetchText(URL(string: "https://seite.test/artikel")!)
        XCTAssertEqual(hit.title, "artikel")
        XCTAssertEqual(hit.domain, "seite.test")
        MockHTTP.install { _ in (200, Data("kurz".utf8)) }
        do {
            _ = try await WebSearch.fetchText(URL(string: "https://seite.test/kurz")!)
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
