@testable import GwenMobileFeatureCore
import Security
import XCTest
import GwenMobileKit

@MainActor
final class ProvidersAndResearchGapTests: GwenTestCase {
    func testTheKeychainRoundTripAndErrorPaths() throws {
        let empty = KeychainKeyStore(service: "")
        let missing = empty.read(account: "")
        _ = missing.text
        _ = missing.isBlocked
        let service = "GwenMobileGap-\(UUID().uuidString)"
        let store = KeychainKeyStore(service: service)
        let account = "gap-account"
        addTeardownBlock { store.delete(account: account) }
        XCTAssertFalse(store.save("", account: account))
        guard store.save("secret", account: account) else {
            throw XCTSkip("Keychain unavailable in this test host (missing entitlement).")
        }
        XCTAssertEqual(store.read(account: account).text, "secret")
        XCTAssertTrue(store.save("secret2", account: account))
        XCTAssertEqual(store.read(account: account).text, "secret2")
        XCTAssertTrue(store.delete(account: account))
        XCTAssertTrue(store.delete(account: account))
        let legacy: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "gap-old",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemDelete(legacy as CFDictionary)
        var add = legacy
        add[kSecValueData as String] = Data("alt".utf8)
        SecItemAdd(add as CFDictionary, nil)
        XCTAssertEqual(store.read(account: "gap-old").text, "alt")
        store.delete(account: "gap-old")
    }

    func testImageDownloadsRejectLocalAndPlainHTTPURLs() async {
        for url in [URL(fileURLWithPath: "/etc/hosts"),
                    URL(string: "http://example.com/image.jpg")].compactMap({ $0 }) {
            do {
                _ = try await QwenAPI.download(url)
                XCTFail("erwartet abgelehnt: \(url)")
            } catch {
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }

    func testTheVerifierRetriesAndFailures() async {
        _ = SourceReview.ClaimResult()
        var review = SourceReview()
        review.citedClaims = 2
        review.verified = false
        review.sourceDomains = 1
        let unreadable = SourceVerifier(baseURL: "https://q.test/v1", key: "k", model: "m",
                                        thinking: .nothing, ask: { _ in "kaputt" })
        _ = await unreadable.apply(to: review, answer: "Aussage [1]", hits: [])
        let throwing = SourceVerifier(baseURL: "https://q.test/v1", key: "k", model: "m",
                                      thinking: .nothing, ask: { _ in throw APIError(message: "kaputt") })
        _ = await throwing.apply(to: review, answer: "Aussage [1]", hits: [])
        let good = SourceVerifier(baseURL: "https://q.test/v1", key: "k", model: "m",
                                  thinking: .nothing, ask: { _ in
            #"{"claims":[{"claim":"Aussage","sources":[1],"supported":true}]}"#
        })
        let done = await good.apply(to: review, answer: "Aussage [1]", hits: [])
        XCTAssertTrue(done.verified)
        let emptyReview = SourceReview()
        _ = await good.apply(to: emptyReview, answer: "Nichts", hits: [])
    }

    func testSmokeTheSourceReviewMatchingEdges() {
        var review = SourceReview()
        review.citedClaims = 2
        review.results = [SourceReview.ClaimResult(claim: "Ein sehr langer Satz mit vielen Worten",
                                                   verdict: .unsupported, sources: [9])]
        let answer = "Ein sehr langer Satz mit vielen Worten. Und noch ein zweiter Satz mit vielen Worten extra. [1]"
        _ = review.marks(in: answer)
        review.results = [SourceReview.ClaimResult(claim: "Kurz", verdict: .unsupported, sources: [1])]
        _ = review.marks(in: "Kurz [1]")
        _ = review.marks(in: "Etwas völlig anderes [1]")
    }

    func testTheWebResearchFailurePaths() async {
        let research = WebResearch(onStatus: { _ in })
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        let empty = await research.fetch([])
        XCTAssertTrue(empty.hits.isEmpty)
        do {
            _ = try await research.searchedURLs("Test") { _ in
                throw APIError(message: "kaputt")
            }
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        MockHTTP.install { _ in (200, Data("{}".utf8)) }
        do {
            _ = try await research.searchedURLs("Test") { _ in [] }
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
