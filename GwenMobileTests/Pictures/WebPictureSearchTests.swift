@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class WebPictureSearchTests: GwenTestCase {
    private func anchor(_ id: String, page: String, full: String, title: String) -> String {
        "<a class=\"iusc\" style=\"height:180px;width:306px\" "
            + "m=\"{&quot;sid&quot;:&quot;&quot;,&quot;purl&quot;:&quot;\(page)&quot;,"
            + "&quot;murl&quot;:&quot;\(full)&quot;,"
            + "&quot;turl&quot;:&quot;https://ts4.mm.bing.net/th?id=\(id)&amp;pid=15.1&quot;,"
            + "&quot;t&quot;:&quot;\(title)&quot;}\"><img src=\"x\">Titel</a>"
    }

    private func page(_ anchors: [String]) -> String {
        "<html><body><div id=\"dgdp\">\(anchors.joined())</div></body></html>"
    }

    func testParseRebuildsOneCleanThumbnailURLPerHit() throws {
        let html = page([anchor("OIP.abc123",
                                page: "https://movieweb.com/cary-elwes/",
                                full: "https://static1.moviewebimages.com/a.jpg",
                                title: "Cary Elwes &amp; Robin Wright")])
        let hits = try XCTUnwrap(BingPictureSearch.hits(from: html).nilIfEmpty)
        let hit = try XCTUnwrap(hits.first)
        XCTAssertEqual(hit.thumbURL, "https://ts4.mm.bing.net/th?id=OIP.abc123&w=\(ImagePolicy.galleryThumbPixel)")
        XCTAssertFalse(hit.thumbURL.contains("pid="), "die fest genagelte Variante bleibt nicht stehen")
        XCTAssertEqual(hit.pageURL, "https://movieweb.com/cary-elwes/")
        XCTAssertEqual(hit.fullURL, "https://static1.moviewebimages.com/a.jpg")
        XCTAssertEqual(hit.domain, "movieweb.com")
        XCTAssertEqual(hit.title, "Cary Elwes & Robin Wright")
    }

    func testParseKeepsEveryDistinctHitAndDropsRepeats() {
        let one = anchor("OIP.one", page: "https://a.test/x", full: "https://a.test/1.jpg", title: "eins")
        let two = anchor("OIP.two", page: "https://b.test/y", full: "https://b.test/2.jpg", title: "zwei")
        XCTAssertEqual(BingPictureSearch.hits(from: page([one, two, one])).count, 2)
    }

    func testParseIgnoresAnchorsWithoutAUsableThumbnail() {
        let broken = "<a class=\"iusc\" m=\"{&quot;purl&quot;:&quot;https://a.test/x&quot;}\">x</a>"
        let httpOnly = "<a class=\"iusc\" m=\"{&quot;turl&quot;:&quot;http://ts4.mm.bing.net/th?id=OIP.x&quot;,"
            + "&quot;purl&quot;:&quot;https://a.test/x&quot;}\">x</a>"
        let localPage = anchor("OIP.loc", page: "file:///etc/hosts", full: "https://a.test/x.jpg",
                               title: "lokal")
        XCTAssertEqual(BingPictureSearch.hits(from: page([broken, httpOnly, localPage])).count, 0)
    }

    func testALocalFullURLFallsBackToTheWebPage() throws {
        let localFull = anchor("OIP.full", page: "https://a.test/x", full: "file:///etc/passwd", title: "Bild")
        let hit = try XCTUnwrap(BingPictureSearch.hits(from: page([localFull])).first)
        XCTAssertEqual(hit.fullURL, "https://a.test/x")
    }

    func testParseFallsBackToTheSourceDomainWhenTheTitleIsMissing() throws {
        let headless = "<a class=\"iusc\" m=\"{&quot;turl&quot;:&quot;https://ts1.mm.bing.net/th?id=OIP.x"
            + "&amp;pid=15.1&quot;,&quot;purl&quot;:&quot;https://de.wikipedia.org/wiki/A&quot;,"
            + "&quot;t&quot;:&quot;   &quot;}\">x</a>"
        let hit = try XCTUnwrap(BingPictureSearch.hits(from: page([headless])).first)
        XCTAssertEqual(hit.title, "de.wikipedia.org")
        XCTAssertEqual(hit.fullURL, "https://de.wikipedia.org/wiki/A", "ohne Originallink bleibt die Quellseite")
    }

    func testParseRefusesAPageWithoutResults() {
        XCTAssertTrue(BingPictureSearch.hits(from: "<html><body>keine treffer</body></html>").isEmpty)
        XCTAssertTrue(BingPictureSearch.hits(from: "").isEmpty)
    }

    func testTheRequestAsksForPhotosInStrictSafeModeAndHonoursPaging() throws {
        let request = try BingPictureSearch.request(query: "aurora borealis", offset: 25)
        let url = try XCTUnwrap(request.url)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("q"), "aurora borealis")
        XCTAssertEqual(value("first"), "25")
        XCTAssertEqual(value("count"), String(ImagePolicy.galleryPageSpan))
        XCTAssertEqual(value("mmasync"), "1")
        XCTAssertEqual(value("qft"), BingPictureSearch.photoFilter)
        XCTAssertEqual(value("safeSearch"), "strict")
        XCTAssertEqual(url.host, "www.bing.com")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"), "ohne Kopfzeile antwortet die Suche nicht")
    }

    func testTheFirstPageNeverAsksForANegativeStart() throws {
        let url = try XCTUnwrap(BingPictureSearch.request(query: "test", offset: 0).url)
        XCTAssertTrue(url.absoluteString.contains("first=1"), url.absoluteString)
    }

    func testAnEmptyQueryIsRefusedBeforeAnyNetworkCall() {
        XCTAssertThrowsError(try BingPictureSearch.request(query: "   \n ", offset: 1)) { error in
            XCTAssertEqual((error as? APIError)?.message, L.t("web_bad_query"))
        }
    }

    func testAnUnbuildableEndpointIsRefused() {
        XCTAssertThrowsError(try BingPictureSearch.request(query: "test", offset: 1, endpoint: "http://[::1")) {
            XCTAssertEqual(($0 as? APIError)?.message, L.t("web_bad_query"))
        }
    }

    func testTheThumbnailRebuildKeepsTheHostOfTheFoundPicture() throws {
        let url = try XCTUnwrap(BingPictureSearch.thumbnailURL(
            from: "https://tse1.mm.bing.net/th?id=OIP.xyz&pid=15.1&q=2"))
        XCTAssertEqual(url, "https://tse1.mm.bing.net/th?id=OIP.xyz&w=\(ImagePolicy.galleryThumbPixel)")
    }

    func testAFormDataLinkOrAMissingIdNeverBecomesAThumbnail() {
        XCTAssertNil(BingPictureSearch.thumbnailURL(from: "https://ts4.mm.bing.net/th?id="))
        XCTAssertNil(BingPictureSearch.thumbnailURL(from: "not a url"))
        XCTAssertNil(BingPictureSearch.thumbnailURL(from: "ftp://ts4.mm.bing.net/th?id=OIP.x"))
    }
}
