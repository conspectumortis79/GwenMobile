import XCTest
@testable import GwenMobile

@MainActor
final class ResearchContextTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    private func hit(_ title: String, _ url: String, _ domain: String, _ text: String) -> WebHit {
        WebHit(title: title, url: url, domain: domain, text: text)
    }

    private func source(_ title: String, _ url: String, _ domain: String) -> WebSource {
        WebSource(title: title, url: url, domain: domain)
    }

    func testHitsDigestNamesEverySourceAndIsCapped() {
        let hits = [hit("Statista", "https://statista.test/a", "statista.test", "83,2 Millionen Menschen"),
                    hit("Wikipedia", "https://de.wikipedia.test/b", "wikipedia.test", "84,7 Millionen im Jahr 2024")]
        let digest = WebResearch.dataDigest(from: hits)
        XCTAssertTrue(digest.contains("## Quelle [1] Statista — statista.test"))
        XCTAssertTrue(digest.contains("83,2 Millionen Menschen"))
        XCTAssertTrue(digest.contains("## Quelle [2] Wikipedia — wikipedia.test"))
        XCTAssertTrue(digest.contains("84,7 Millionen im Jahr 2024"))
        XCTAssertEqual(WebResearch.sources(from: hits).map(\.domain), ["statista.test", "wikipedia.test"])
        XCTAssertEqual(WebResearch.dataDigest(from: hits, limit: 40).count, 40)
    }

    func testPriorResearchFeedsThePreviousAnswerAndItsSources() {
        let answer = ChatMessage(role: .assistant, text: "2020: 83,2 Mio.\n2024: 84,7 Mio.",
                                 sources: [source("Statista", "https://statista.test/e", "statista.test")])
        let history = [ChatMessage(role: .user, text: "Wie viele Einwohner hat Deutschland?"), answer]
        let prior = WebResearch.priorResearch(from: history)
        XCTAssertTrue(prior.digest.contains("## Gespeicherte Antwort"))
        XCTAssertTrue(prior.digest.contains("2024: 84,7 Mio."))
        XCTAssertTrue(prior.digest.contains("## Gefundene Quellen"))
        XCTAssertTrue(prior.digest.contains("Quelle [1] Statista — statista.test https://statista.test/e"))
        XCTAssertEqual(prior.sources.map(\.url), ["https://statista.test/e"])
    }

    func testPriorResearchUsesTheLastAnswersAndTheirNewestSources() {
        var history: [ChatMessage] = []
        for index in 1...4 {
            history.append(ChatMessage(role: .user, text: "frage \(index)"))
            history.append(ChatMessage(role: .assistant, text: "antwort \(index)",
                                       sources: index < 4 ? [source("Alt\(index)", "https://alt.test", "alt.test")] : nil))
        }
        history.append(ChatMessage(role: .assistant, text: "   "))
        let prior = WebResearch.priorResearch(from: history)
        XCTAssertTrue(prior.digest.contains("antwort 4"))
        XCTAssertTrue(prior.digest.contains("antwort 3"))
        XCTAssertFalse(prior.digest.contains("antwort 2"))
        XCTAssertEqual(prior.digest.components(separatedBy: "## Gespeicherte Antwort").count - 1,
                       WebResearch.maxPriorAnswers)
        XCTAssertEqual(prior.sources.map(\.title), ["Alt3"], "Quellen der letzten Recherche mit Quellen")
    }

    func testPriorResearchIsEmptyWithoutAnyAnswer() {
        let empty: [ChatMessage] = []
        XCTAssertEqual(WebResearch.priorResearch(from: empty).digest, "")
        XCTAssertTrue(WebResearch.priorResearch(from: empty).sources.isEmpty)
        let onlyQuestions = WebResearch.priorResearch(from: [ChatMessage(role: .user, text: "nur eine frage")])
        XCTAssertEqual(onlyQuestions.digest, "")
        XCTAssertTrue(onlyQuestions.sources.isEmpty)
    }
}
