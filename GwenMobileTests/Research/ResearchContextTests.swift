@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class ResearchContextTests: GwenTestCase {
    func testOneReadableSourceIsEnough() {
        XCTAssertEqual(WebResearch.minimumSourceCount, 1)
        XCTAssertEqual(WebSearch.resultLimit, 5)
        XCTAssertTrue(L.t("web_search_prompt").contains(SearchMarker.token))
    }

    private func researchRequest() throws -> (system: String, user: String) {
        let request = try WebSearch.makeAnswerRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                      question: "frage",
                                                      hits: [Fixtures.hit("T", "https://a.test", "a.test", "text")],
                                                      thinking: .nothing)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        return (try XCTUnwrap(messages.first?["content"] as? String),
                try XCTUnwrap(messages.last?["content"] as? String))
    }

    func testResearchPromptHandlesASingleSource() throws {
        let (system, _) = try researchRequest()
        XCTAssertTrue(system.contains("If there is only one source, use it and say so"))
    }

    func testTheCompactResearchPromptKeepsItsWordLimit() throws {
        let (system, _) = try researchRequest()
        XCTAssertTrue(system.contains("factually and compactly (at most 150 words). If the sources"), system)
        XCTAssertFalse(system.contains("in depth"))
    }

    func testADetailedResearchPromptNamesEveryItemAndItsRoom() {
        let prompt = Prompt.Research.webAnswer(length: .detailed(items: 5))
        XCTAssertTrue(prompt.contains("in depth (at most 400 words)"), prompt)
        XCTAssertTrue(prompt.contains("The earlier answer listed 5 items"), prompt)
        XCTAssertTrue(prompt.contains("about 80 words each"), prompt)
        XCTAssertTrue(prompt.contains("Never pad an item"), prompt)
        XCTAssertFalse(prompt.contains("compactly"))
    }

    func testADetailedPromptWithoutEarlierItemsAsksOnlyForDepth() {
        let prompt = Prompt.Research.webAnswer(length: .detailed(items: 0))
        XCTAssertTrue(prompt.contains("in depth (at most \(AnswerLength.detailedFloor) words)"), prompt)
        XCTAssertFalse(prompt.contains("The earlier answer listed"))
    }

    func testTheResearchRequestCarriesTheChosenLength() throws {
        let request = try WebSearch.makeAnswerRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                      question: "frage",
                                                      hits: [Fixtures.hit("T", "https://a.test", "a.test", "text")],
                                                      length: .detailed(items: 3), thinking: .nothing)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(system.contains("in depth (at most 300 words)"), system)
        XCTAssertTrue(system.contains("listed 3 items"), system)
    }

    func testTheResearchAnswerIsNeverAskedForTheSearchToken() throws {
        let (system, _) = try researchRequest()
        XCTAssertFalse(system.contains(SearchMarker.token),
                       "ein nacktes Such-Token wäre nach der Recherche leer und würde die Antwort schlucken")
    }

    func testEverySourceCarriesItsCheckLine() {
        let hit = Fixtures.hit("Statista", "https://statista.test/a", "statista.test", "83,2 Millionen")
        XCTAssertTrue(hit.sourceBlock(numbered: 1).contains("Source check: nothing found"))
        var dated = hit
        dated.metadata.published = "2024-05-01"
        XCTAssertTrue(dated.sourceBlock(numbered: 1).contains("date 2024-05-01"))
    }

    func testADuplicateSourceIsMarkedInTheBlock() {
        let hit = Fixtures.hit("Statista", "https://a.test/x", "a.test", "Text")
        XCTAssertTrue(hit.sourceBlock(numbered: 2, copyOf: 1).contains("Duplicate of source [1]"))
        XCTAssertFalse(hit.sourceBlock(numbered: 1).contains("Duplicate"))
    }

    func testThePromptsMarkCopiesOfOneAgencyText() {
        let text = "Der Bundestag hat am Mittwoch ein Gesetz beschlossen, das neue Gasheizungen ab 2027 "
            + "verbietet. Die Regelung gilt für Neubauten und sieht Übergangsfristen vor. Die Opposition "
            + "kritisierte den Zeitplan als zu knapp."
        let hits = [Fixtures.hit("A", "https://a.test/x", "a.test", text),
                    Fixtures.hit("B", "https://b.test/y", "b.test", text)]
        let context = WebSearch.answerContext(question: "frage", hits: hits, history: [])
        XCTAssertTrue((context as? String ?? "").contains("Duplicate of source [1]"))
        XCTAssertTrue(SourceVerifier.userContext(answer: "Aussage [1][2].", hits: hits)
            .contains("Duplicate of source [1]"))
    }

    func testTheAnswerPromptNamesTheOneWebsite() throws {
        let hits = [Fixtures.hit("A", "https://a.test/x", "a.test", "text"),
                    Fixtures.hit("B", "https://www.a.test/y", "www.a.test", "text")]
        let request = try WebSearch.makeAnswerRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                      question: "frage", hits: hits, thinking: .nothing)
        let system = try XCTUnwrap(jsonMessages(of: request).first?["content"] as? String)
        XCTAssertTrue(system.contains("All sources come from the same website (a.test)"), system)
    }

    func testTheAnswerPromptStaysSilentAboutCoverageWithSeveralWebsites() throws {
        let hits = [Fixtures.hit("A", "https://a.test/x", "a.test", "text"),
                    Fixtures.hit("B", "https://b.test/y", "b.test", "text")]
        let request = try WebSearch.makeAnswerRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                      question: "frage", hits: hits, thinking: .nothing)
        let system = try XCTUnwrap(jsonMessages(of: request).first?["content"] as? String)
        XCTAssertFalse(system.contains("All sources come from the same website"), system)
    }

    func testTheSourceNoteReachesTheSystemPrompt() {
        XCTAssertTrue(Prompt.Research.webAnswer(sourceNote: "Same website only.")
            .contains("Same website only."))
        XCTAssertFalse(Prompt.Research.webAnswer().contains("{{"))
    }

    func testAnswerPromptAndDigestShareOneSourceBlockFormat() throws {
        let hits = [Fixtures.hit("Statista", "https://statista.test/a", "statista.test", "83,2 Millionen")]
        let request = try WebSearch.makeAnswerRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                      question: "frage", hits: hits, thinking: .nothing)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(user.contains(hits[0].sourceBlock(numbered: 1)))
        XCTAssertEqual(WebResearch.sources(from: hits).map(\.domain), ["statista.test"])
    }

    func testDomainOnlyLosesALeadingWwwPrefix() {
        XCTAssertEqual(WebSearch.domain(of: URL(string: "https://www.statista.com/x")!), "statista.com")
        XCTAssertEqual(WebSearch.domain(of: URL(string: "https://shopwww.example.com/x")!), "shopwww.example.com")
    }

    func testResearchAnswerRemembersWhatWasTalkedAboutBefore() throws {
        let history = [ChatMessage(role: .user, text: "Wie viele Einwohner hat Deutschland?"),
                       ChatMessage(role: .assistant, text: "2024 waren es 84,7 Millionen."),
                       ChatMessage(role: .user, text: "und in österreich?")]
        let request = try WebSearch.makeAnswerRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                      question: "Einwohnerzahl Österreich 2024",
                                                      hits: [Fixtures.hit("Statista", "https://a.test", "a.test", "9,2 Millionen")],
                                                      history: history, thinking: .nothing)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(content.contains("## EARLIER CONVERSATION"))
        XCTAssertTrue(content.contains("84,7 Millionen"))
        XCTAssertFalse(content.contains("und in österreich?"), "die eigene neue Frage ist kein Kontext")
        XCTAssertTrue(content.contains("## SOURCE [1] Statista"))
        XCTAssertTrue(content.hasSuffix("Einwohnerzahl Österreich 2024"))
    }

    func testResearchAnswerWithoutHistoryStaysWithTheSourcesAlone() throws {
        let (system, user) = try researchRequest()
        XCTAssertFalse(user.contains("## EARLIER CONVERSATION"))
        XCTAssertTrue(system.contains("EARLIER CONVERSATION"))
    }

    func testTheResearchAnswerCarriesThePictureTheQuestionMeans() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let hits = [Fixtures.hit("Idealo", "https://idealo.de/a", "idealo.de", "612,00 €")]
        let request = try WebSearch.makeAnswerRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                     question: "frage", hits: hits, history: [],
                                                     images: [jpeg, jpeg, jpeg], thinking: .nothing)
        let messages = try XCTUnwrap((try XCTUnwrap(JSONSerialization.jsonObject(
            with: request.httpBody ?? Data()) as? [String: Any]))["messages"] as? [[String: Any]])
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(system.contains("never as a source of prices"), system)
        let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 1 + WebSearch.maxAnswerImages)
        XCTAssertTrue((parts.first?["text"] as? String ?? "").contains("## SOURCE [1]"))
        XCTAssertTrue(parts[1]["image_url"] != nil)
    }

    func testWithoutAPictureTheResearchRequestStaysPlainText() throws {
        let request = try WebSearch.makeAnswerRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                     question: "frage",
                                                     hits: [Fixtures.hit("Idealo", "https://idealo.de/a",
                                                                        "idealo.de", "612,00 €")],
                                                     history: [], thinking: .nothing)
        let messages = try XCTUnwrap((try XCTUnwrap(JSONSerialization.jsonObject(
            with: request.httpBody ?? Data()) as? [String: Any]))["messages"] as? [[String: Any]])
        XCTAssertTrue(messages.last?["content"] is String)
    }

    func testEmptySearchGetsOneRetryAndSaysSo() async throws {
        let calls = LockedValue(0)
        var statuses: [String] = []
        let research = WebResearch(onStatus: { statuses.append($0) })
        let urls = try await research.searchedURLs("frage", attempts: 2, backoff: .milliseconds(5)) { _ in
            let attempt = calls.mutate { stored in stored += 1; return stored }
            return attempt == 1 ? [] : [URL(string: "https://a.test/x")!]
        }
        XCTAssertEqual(calls.current, 2)
        XCTAssertEqual(urls.map(\.host), ["a.test"])
        XCTAssertEqual(statuses, [L.t("web_searching_again")])
    }

    func testExhaustedSearchStopsAtTheAttemptLimit() async throws {
        let calls = LockedValue(0)
        let research = WebResearch(onStatus: { _ in })
        let urls = try await research.searchedURLs("frage", attempts: 3, backoff: .milliseconds(5)) { _ in
            calls.mutate { stored in stored += 1 }
            return []
        }
        XCTAssertTrue(urls.isEmpty)
        XCTAssertEqual(calls.current, 3)
    }

    func testTransportFailureIsNotRetried() async throws {
        let calls = LockedValue(0)
        let research = WebResearch(onStatus: { _ in })
        do {
            _ = try await research.searchedURLs("frage", attempts: 2, backoff: .milliseconds(5)) { _ in
                calls.mutate { stored in stored += 1 }
                throw APIError(message: "HTTP 503")
            }
            XCTFail("Der Transportfehler hätte durchkommen müssen")
        } catch {
            XCTAssertEqual((error as? APIError)?.message, "HTTP 503")
        }
        XCTAssertEqual(calls.current, 1)
    }
}

final class DuckDuckGoLinkTests: XCTestCase {
    func testARedirectWrapperIsUnwrappedToItsTarget() {
        XCTAssertEqual(WebSearch.resolvedHref("//duckduckgo.com/l/?uddg=https%3A%2F%2Fde.wikipedia.org%2Fwiki%2FBerlin&rut=abc"),
                       "https://de.wikipedia.org/wiki/Berlin")
    }

    func testAnAbsoluteRedirectKeepsItsOwnShape() {
        XCTAssertEqual(WebSearch.resolvedHref("https://html.duckduckgo.com/l/?uddg=https%3A%2F%2Fx.example%2Fa"),
                       "https://x.example/a")
    }

    func testAPlainResultURLPassesThroughUntouched() {
        XCTAssertEqual(WebSearch.resolvedHref("https://example.org/preise"), "https://example.org/preise")
        XCTAssertEqual(WebSearch.resolvedHref("/preisuebersicht"), "/preisuebersicht")
    }

    func testAnEncodedTargetKeepsItsOwnEscapes() {
        XCTAssertEqual(WebSearch.resolvedHref("https://duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fwiki%2FA%252FB"),
                       "https://example.com/wiki/A%2FB")
        XCTAssertEqual(WebSearch.resolvedHref("https://duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fa%253Fb"),
                       "https://example.com/a%3Fb")
    }
}
