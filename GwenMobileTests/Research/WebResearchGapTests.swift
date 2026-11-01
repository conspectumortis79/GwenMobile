@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class WebResearchGapTests: GwenTestCase {
    private let page = "<html><head><title>Testseite</title></head><body><p>"
        + String(repeating: "Ein langer Text über das Wetter und die Welt. ", count: 40)
        + "</p></body></html>"

    func testAShortPageIsAFetchFailure() async {
        MockHTTP.install { _ in (200, Data("<html><body>zu kurz</body></html>".utf8)) }
        defer { MockHTTP.uninstall() }
        do {
            _ = try await WebSearch.fetchText(URL(string: "https://kurz.test/a")!)
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testACancelledFetchStopsTheGroup() async {
        let page = self.page
        MockHTTP.install { _ in (200, Data(page.utf8)) }
        MockHTTPProtocol.dataDelay = 0.2
        defer { MockHTTP.uninstall() }
        let research = WebResearch(onStatus: { _ in })
        let urls = (0..<8).map { URL(string: "https://seite\($0).test/a")! }
        let task = Task { await research.fetch(urls) }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        let result = await task.value
        XCTAssertLessThanOrEqual(result.hits.count, urls.count)
    }

    func testTheFetchAndSearchPaths() async {
        let research = WebResearch(onStatus: { _ in })
        let page = self.page
        MockHTTP.install { request in
            let address = request.url?.absoluteString ?? ""
            if address.contains("duckduckgo") {
                let html = """
                <a class="result__a" href="https://eins.test/a">Eins</a>
                <a class="result__a" href="https://zwei.test/b">Zwei</a>
                <a class="result__a" href="https://drei.test/c">Drei</a>
                <a class="result__a" href="https://vier.test/d">Vier</a>
                <a class="result__a" href="https://fuenf.test/e">Fünf</a>
                <a class="result__a" href="https://sechs.test/f">Sechs</a>
                <a class="result__a" href="https://sieben.test/g">Sieben</a>
                """
                return (200, Data(html.utf8))
            }
            if address.contains("kaputt.test") {
                return (500, Data("kaputt".utf8))
            }
            return (200, Data(page.utf8))
        }
        defer { MockHTTP.uninstall() }
        _ = try? await research.hits(for: "Wetter morgen")
        let empty = await research.fetch([])
        XCTAssertTrue(empty.hits.isEmpty)
        let many = await research.fetch((0..<8).map { URL(string: "https://seite\($0).test/a")! })
        XCTAssertEqual(many.hits.count, 8)
        let broken = await research.fetch([URL(string: "https://kaputt.test/a")!])
        XCTAssertEqual(broken.failures.count, 1)
        let urls = try? await research.searchedURLs("Test", via: { _ in [URL(string: "https://eins.test/a")!] })
        XCTAssertFalse(urls?.isEmpty ?? true)
        do {
            _ = try await research.searchedURLs("Test", via: { _ in throw APIError(message: "kaputt") })
            XCTFail("erwartet Fehler")
        } catch {}
        _ = try? await research.searchedURLs("Test", attempts: 1, backoff: .milliseconds(1), via: { _ in [] })
        let webSources = WebResearch.sources(from: [WebHit(title: "T", url: "https://a.test/x",
                                                           domain: "a.test", text: "Inhalt")])
        XCTAssertEqual(webSources.first?.domain, "a.test")
        MockHTTP.install { _ in (200, Data("<html></html>".utf8)) }
        do {
            _ = try await research.hits(for: "Leer", via: { _ in [URL(string: "https://leer.test/a")!] })
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
