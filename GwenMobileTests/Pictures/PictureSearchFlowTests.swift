@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

private struct SearchFailed: Error {}
private struct FetchFailed: Error {}

@MainActor
final class PictureSearchFlowTests: GwenTestCase {

    private func hit(_ number: Int) -> PictureHit {
        PictureHit(thumbURL: "https://ts4.mm.bing.net/th?id=OIP.\(number)&w=720",
                   pageURL: "https://q\(number).test/seite",
                   fullURL: "https://cdn.q\(number).test/original.jpg",
                   title: "Bild \(number)", domain: "q\(number).test")
    }

    private func hits(_ count: Int) -> [PictureHit] {
        (1...count).map { hit($0) }
    }

    private func thumbURLs(_ count: Int) -> Set<String> {
        Set(hits(count).map(\.thumbURL))
    }

    func testEveryDownloadedPictureKeepsTheOrderOfTheSearch() async throws {
        let store = scratchMediaStore()
        let found = hits(4)
        let flow = PictureSearchFlow(search: FakeSearching(results: found),
                                     fetch: FakeFetching(recorder: LockedValue([])),
                                     media: store)
        let round = try await flow.run(query: "cary elwes")
        XCTAssertEqual(round.pictures.map(\.title), ["Bild 1", "Bild 2", "Bild 3", "Bild 4"])
        XCTAssertEqual(Set(store.fileNames()), Set(round.pictures.map(\.file)))
        XCTAssertEqual(round.pictures.first?.fullURL, "https://cdn.q1.test/original.jpg")
        XCTAssertEqual(round.pictures.first?.pageURL, "https://q1.test/seite")
    }

    func testAFailingSourceOnlyCostsItsOwnTile() async throws {
        let store = scratchMediaStore()
        let found = hits(3)
        let flow = PictureSearchFlow(search: FakeSearching(results: found),
                                     fetch: FakeFetching(failing: [found[1].thumbURL],
                                                        recorder: LockedValue([])),
                                     media: store)
        let round = try await flow.run(query: "nordlicht")
        XCTAssertEqual(round.pictures.map(\.domain), ["q1.test", "q3.test"])
        XCTAssertEqual(round.failures, 1)
        XCTAssertEqual(store.fileNames().count, 2)
    }

    func testTheRoundPointsAtTheNextPageAndKnowsWhenTheSearchIsOver() async throws {
        let store = scratchMediaStore()
        let shortPage = PictureSearchFlow(search: FakeSearching(results: hits(3)),
                                          fetch: FakeFetching(recorder: LockedValue([])), media: store)
        let first = try await shortPage.run(query: "a", offset: 1)
        XCTAssertEqual(first.nextOffset, 4)
        XCTAssertTrue(first.exhausted)

        let fullPage = PictureSearchFlow(search: FakeSearching(results: hits(ImagePolicy.galleryPageSpan)),
                                         fetch: FakeFetching(recorder: LockedValue([])), media: store)
        let second = try await fullPage.run(query: "a", offset: 25)
        XCTAssertEqual(second.nextOffset, 25 + ImagePolicy.galleryMaxStored)
        XCTAssertFalse(second.exhausted)

        let partialPage = PictureSearchFlow(search: FakeSearching(results: hits(ImagePolicy.galleryMaxStored + 2)),
                                            fetch: FakeFetching(recorder: LockedValue([])), media: store)
        let partial = try await partialPage.run(query: "a", offset: 1)
        XCTAssertEqual(partial.nextOffset, 1 + ImagePolicy.galleryMaxStored)
        XCTAssertFalse(partial.exhausted)
    }

    func testTheStoreCapsAtTheBudgetAndNeverFetchesMore() async throws {
        let seen = LockedValue([String]())
        let flow = PictureSearchFlow(search: FakeSearching(results: hits(ImagePolicy.galleryPageSpan)),
                                     fetch: FakeFetching(recorder: seen), media: scratchMediaStore())
        let round = try await flow.run(query: "aurora")
        XCTAssertEqual(round.pictures.count, ImagePolicy.galleryMaxStored)
        XCTAssertEqual(Set(seen.current), thumbURLs(ImagePolicy.galleryMaxStored))
    }

    func testAnEmptySearchIsReportedAsNoPictureHit() async throws {
        let flow = PictureSearchFlow(search: FakeSearching(results: []),
                                     fetch: FakeFetching(recorder: LockedValue([])), media: scratchMediaStore())
        var thrown: Error?
        do { _ = try await flow.run(query: "nichts") } catch { thrown = error }
        XCTAssertEqual((thrown as? APIError)?.message, L.t("pictures_none_found"))
    }

    func testATransportErrorFromTheSearchStaysVisible() async throws {
        let flow = PictureSearchFlow(search: FakeSearching(results: [], failure: SearchFailed()),
                                     fetch: FakeFetching(recorder: LockedValue([])), media: scratchMediaStore())
        var thrown: Error?
        do { _ = try await flow.run(query: "irgendwas") } catch { thrown = error }
        XCTAssertTrue(thrown is SearchFailed)
    }

    func testNothingSurvivingTheDownloadIsItsOwnError() async throws {
        let flow = PictureSearchFlow(search: FakeSearching(results: hits(2)),
                                     fetch: FakeFetching(failing: thumbURLs(2),
                                                        recorder: LockedValue([])),
                                     media: scratchMediaStore())
        var thrown: Error?
        do { _ = try await flow.run(query: "aurora") } catch { thrown = error }
        XCTAssertEqual((thrown as? APIError)?.message, L.t("pictures_load_failed"))
    }

    func testEveryPictureOfARoundIsOnTheDiskBeforeTheAnswerIsWritten() async throws {
        let store = scratchMediaStore()
        let flow = PictureSearchFlow(search: FakeSearching(results: hits(3)),
                                     fetch: FakeFetching(recorder: LockedValue([])), media: store)
        let round = try await flow.run(query: "denkmal")
        XCTAssertTrue(round.pictures.allSatisfy { store.hasImage($0.file) })
        XCTAssertNotNil(store.data(named: try XCTUnwrap(round.pictures.first?.file)))
    }

    func testStoringRefusesHitsTheSearchDidNotAskFor() {
        let store = scratchMediaStore()
        let stored = PictureSearchFlow.store([(7, FakePictureData.jpeg()), (0, FakePictureData.jpeg())],
                                             over: hits(2), media: store)
        XCTAssertEqual(stored.map(\.title), ["Bild 1"])
    }
}

private struct FakeSearching: PictureSearching {
    let results: [PictureHit]
    var failure: Error?

    func pictures(for query: String, offset: Int) async throws -> [PictureHit] {
        if let failure { throw failure }
        return results
    }
}

private struct FakeFetching: RemoteImageFetching {
    var failing: Set<String> = []
    let recorder: LockedValue<[String]>
    var bytes: Data = FakePictureData.jpeg()

    func data(from url: URL) async throws -> Data {
        recorder.mutate { seen in seen.append(url.absoluteString) }
        guard !failing.contains(url.absoluteString) else { throw FetchFailed() }
        return bytes
    }
}

enum FakePictureData {
    static func jpeg() -> Data {
        guard let data = FakePicture.make(CGSize(width: 60, height: 40)).jpegData(compressionQuality: 0.6)
        else { XCTFail("Testbild ließ sich nicht kodieren"); return Data() }
        return data
    }
}
