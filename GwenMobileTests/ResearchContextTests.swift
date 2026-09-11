import XCTest
@testable import GwenMobile

@MainActor
final class ResearchContextTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    func testOneReadableSourceIsEnough() {
        XCTAssertEqual(WebResearch.minimumSourceCount, 1)
        XCTAssertEqual(WebSearch.minimumResultCount, 1)
        XCTAssertTrue(L.t("web_search_prompt").contains(SearchMarker.token))
    }

    func testResearchPromptHandlesASingleSource() throws {
        let request = try WebSearch.makeAnswerRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                      question: "frage",
                                                      hits: [Fixtures.hit("T", "https://a.test", "a.test", "text")])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(system.contains("Gibt es nur eine Quelle, nutze sie"))
    }

    func testHitsDigestNamesEverySourceAndIsCapped() {
        let hits = [Fixtures.hit("Statista", "https://statista.test/a", "statista.test", "83,2 Millionen Menschen"),
                    Fixtures.hit("Wikipedia", "https://de.wikipedia.test/b", "wikipedia.test", "84,7 Millionen im Jahr 2024")]
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
                                 sources: [Fixtures.source("Statista", "https://statista.test/e", "statista.test")])
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
                                       sources: index < 4 ? [Fixtures.source("Alt\(index)", "https://alt.test", "alt.test")] : nil))
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

    func testResearchAnswerRemembersWhatWasTalkedAboutBefore() throws {
        let history = [ChatMessage(role: .user, text: "Wie viele Einwohner hat Deutschland?"),
                       ChatMessage(role: .assistant, text: "2024 waren es 84,7 Millionen."),
                       ChatMessage(role: .user, text: "und in österreich?")]
        let request = try WebSearch.makeAnswerRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                      question: "Einwohnerzahl Österreich 2024",
                                                      hits: [Fixtures.hit("Statista", "https://a.test", "a.test", "9,2 Millionen")],
                                                      history: history)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(content.contains("## Bisheriger Verlauf"))
        XCTAssertTrue(content.contains("84,7 Millionen"))
        XCTAssertFalse(content.contains("und in österreich?"), "die eigene neue Frage ist kein Kontext")
        XCTAssertTrue(content.contains("## Quelle [1] Statista"))
        XCTAssertTrue(content.hasSuffix("Einwohnerzahl Österreich 2024"))
    }

    func testResearchAnswerWithoutHistoryStaysWithTheSourcesAlone() throws {
        let request = try WebSearch.makeAnswerRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                      question: "frage",
                                                      hits: [Fixtures.hit("T", "https://a.test", "a.test", "text")])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertFalse(content.contains("## Bisheriger Verlauf"))
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(system.contains("Bisheriger Verlauf"))
    }
}
