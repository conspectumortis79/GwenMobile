@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class WebSourceGatheringTests: XCTestCase {
    private struct Boom: Error {}

    private func hit(_ domain: String) -> WebHit {
        WebHit(title: domain, url: "https://\(domain)", domain: domain, text: "Text zu \(domain).")
    }

    private let question = "Nachrichten aus Musterstadt am See"
    private let query = "aktuelle nachrichten"

    func testAKeptFirstAttemptDoesNotRetry() async throws {
        var terms: [String] = []
        let kept = try await WebSourceGathering.gather(
            query: query, question: question,
            retrieve: { term in terms.append(term); return [self.hit("news.test")] },
            filter: { $0 })
        XCTAssertEqual(terms, [query])
        XCTAssertEqual(kept.map(\.domain), ["news.test"])
    }

    func testAnEmptyFilterRetriesWithTheOriginalQuestion() async throws {
        var terms: [String] = []
        var retried = false
        let kept = try await WebSourceGathering.gather(
            query: query, question: question,
            retrieve: { term in
                terms.append(term)
                return [self.hit(term.contains("Musterstadt") ? "musterstadt.test" : "news.test")]
            },
            filter: { $0.map(\.domain) == ["news.test"] ? [] : $0 },
            onRetry: { retried = true })
        XCTAssertTrue(retried)
        XCTAssertEqual(terms, [query, question])
        XCTAssertEqual(kept.map(\.domain), ["musterstadt.test"])
    }

    func testTheSameTextIsNeverSearchedTwice() async throws {
        var terms: [String] = []
        let kept = try await WebSourceGathering.gather(
            query: "Aktuelle Nachrichten", question: "aktuelle nachrichten",
            retrieve: { term in terms.append(term); return [self.hit("news.test")] },
            filter: { _ in [] })
        XCTAssertEqual(terms.count, 1)
        XCTAssertTrue(kept.isEmpty)
    }

    func testAnEmptyQuestionIsNeverUsedForASecondSearch() async throws {
        var terms: [String] = []
        _ = try await WebSourceGathering.gather(
            query: query, question: "   \n ",
            retrieve: { term in terms.append(term); return [self.hit("news.test")] },
            filter: { _ in [] })
        XCTAssertEqual(terms.count, 1)
    }

    func testBothAttemptsWithoutSourcesEndEmpty() async throws {
        var terms: [String] = []
        let kept = try await WebSourceGathering.gather(
            query: query, question: question,
            retrieve: { term in terms.append(term); return [self.hit("news.test")] },
            filter: { _ in [] })
        XCTAssertEqual(terms.count, 2)
        XCTAssertTrue(kept.isEmpty)
    }

    func testAFailingRetryTravelsUp() async {
        do {
            _ = try await WebSourceGathering.gather(
                query: query, question: question,
                retrieve: { term in
                    if term.contains("Musterstadt") { throw Boom() }
                    return [self.hit("news.test")]
                },
                filter: { _ in [] })
            XCTFail("der Fehler der Wiederholung muss oben ankommen")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }

    func testAFailingFirstAttemptIsNotRetried() async {
        var terms: [String] = []
        do {
            _ = try await WebSourceGathering.gather(
                query: query, question: question,
                retrieve: { term in terms.append(term); throw Boom() },
                filter: { $0 })
            XCTFail("der Fehler des ersten Versuchs muss oben ankommen")
        } catch {
            XCTAssertTrue(error is Boom)
        }
        XCTAssertEqual(terms.count, 1)
    }
}
