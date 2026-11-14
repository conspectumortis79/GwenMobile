@testable import GwenMobileFeatureCore
import XCTest
import Combine
import UIKit
import GwenMobileKit

private final class FakeRenditionReader: ImageRenditionReading, @unchecked Sendable {
    private let lock = NSLock()
    private var cachedImages: [String: UIImage] = [:]
    private var cachedRatios: [String: CGFloat] = [:]
    private var headerRatios: [String: CGFloat] = [:]
    private var decodable: [String: UIImage] = [:]
    private var decodeGate: DispatchSemaphore?
    private(set) var decodeCalls: [String] = []
    private(set) var headerReads: [String] = []

    func cache(_ file: String, image: UIImage, ratio: CGFloat) {
        lock.withLock { cachedImages[file] = image; cachedRatios[file] = ratio }
    }

    func cacheImageOnly(_ file: String, image: UIImage) {
        lock.withLock { cachedImages[file] = image }
    }

    func onDisk(_ file: String, image: UIImage, ratio: CGFloat) {
        lock.withLock { decodable[file] = image; headerRatios[file] = ratio }
    }

    func cachedDisplayImage(named file: String) -> UIImage? { lock.withLock { cachedImages[file] } }

    func decodedDisplayImage(named file: String) -> UIImage? {
        lock.withLock { decodeCalls.append(file) }
        lock.withLock { decodeGate }?.wait()
        return lock.withLock { decodable[file] }
    }

    func cachedDisplayRatio(named file: String) -> CGFloat? { lock.withLock { cachedRatios[file] } }

    func displayRatio(named file: String) -> CGFloat {
        lock.withLock { headerReads.append(file); return headerRatios[file] ?? 1 }
    }

    func holdDecode() {
        lock.withLock { decodeGate = DispatchSemaphore(value: 0) }
    }

    func releaseDecode() {
        lock.withLock { _ = decodeGate?.signal() }
    }
}

@MainActor
final class ImageFeedTests: XCTestCase {
    func testTheRatioIsKnownBeforeAnyBitmapWasDecoded() {
        let reader = FakeRenditionReader()
        reader.onDisk("wide.jpg", image: FakePicture.make(), ratio: 1.5)
        let feed = ImageFeed(reader: reader)
        XCTAssertEqual(feed.ratio(for: "wide.jpg"), 1.5, accuracy: 0.001)
        XCTAssertNil(feed.rendition(for: "wide.jpg"))
        XCTAssertTrue(reader.decodeCalls.isEmpty)
    }

    func testACachedRatioWinsOverTheHeaderRead() {
        let reader = FakeRenditionReader()
        reader.cache("cached.jpg", image: FakePicture.make(), ratio: 0.5)
        let feed = ImageFeed(reader: reader)
        XCTAssertEqual(feed.ratio(for: "cached.jpg"), 0.5, accuracy: 0.001)
        XCTAssertTrue(reader.headerReads.isEmpty)
    }

    func testACachedBitmapIsPublishedAfterTheCallReturnsNotDuringIt() async {
        let reader = FakeRenditionReader()
        let picture = FakePicture.make()
        reader.cache("cached.jpg", image: picture, ratio: 2)
        let feed = ImageFeed(reader: reader)
        feed.load("cached.jpg")
        XCTAssertNil(feed.rendition(for: "cached.jpg"), "Die Veröffentlichung darf nicht im laufenden View-Update passieren")
        await waitUntil { feed.rendition(for: "cached.jpg") != nil }
        XCTAssertTrue(feed.rendition(for: "cached.jpg")?.image === picture)
        XCTAssertEqual(feed.rendition(for: "cached.jpg")?.ratio ?? 0, 2, accuracy: 0.001)
        XCTAssertTrue(reader.decodeCalls.isEmpty)
    }

    func testAnUncachedBitmapIsDecodedOnceAndThenPublished() async {
        let reader = FakeRenditionReader()
        reader.onDisk("disk.jpg", image: FakePicture.make(), ratio: 0.75)
        let feed = ImageFeed(reader: reader)
        feed.load("disk.jpg")
        feed.load("disk.jpg")
        await waitUntil { feed.rendition(for: "disk.jpg") != nil }
        XCTAssertEqual(reader.decodeCalls, ["disk.jpg"])
        XCTAssertEqual(feed.rendition(for: "disk.jpg")?.ratio ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(feed.ratio(for: "disk.jpg"), 0.75, accuracy: 0.001)
    }

    func testRetainingOnlyTheCurrentFilesDropsEveryOtherRendition() async {
        let reader = FakeRenditionReader()
        reader.onDisk("keep.jpg", image: FakePicture.make(), ratio: 1)
        reader.onDisk("drop.jpg", image: FakePicture.make(), ratio: 1)
        let feed = ImageFeed(reader: reader)
        feed.load("keep.jpg")
        feed.load("drop.jpg")
        await waitUntil { feed.rendition(for: "keep.jpg") != nil && feed.rendition(for: "drop.jpg") != nil }
        feed.retain(only: ["keep.jpg"])
        XCTAssertNotNil(feed.rendition(for: "keep.jpg"))
        XCTAssertNil(feed.rendition(for: "drop.jpg"))
    }

    func testRetainingWithoutAnythingStaleDoesNotAnnounceAChange() async {
        let reader = FakeRenditionReader()
        reader.onDisk("keep.jpg", image: FakePicture.make(), ratio: 1)
        let feed = ImageFeed(reader: reader)
        feed.load("keep.jpg")
        await waitUntil { feed.rendition(for: "keep.jpg") != nil }
        var signals = 0
        let token = feed.objectWillChange.sink { _ in signals += 1 }
        feed.retain(only: ["keep.jpg", "other.jpg"])
        XCTAssertEqual(signals, 0)
        token.cancel()
    }

    func testAnInflightDecodeThatLostItsRetentionNeverLands() async throws {
        let reader = FakeRenditionReader()
        reader.onDisk("drop.jpg", image: FakePicture.make(), ratio: 1)
        reader.holdDecode()
        let feed = ImageFeed(reader: reader)
        feed.load("drop.jpg")
        await waitUntil { reader.decodeCalls == ["drop.jpg"] }
        feed.retain(only: [])
        reader.releaseDecode()
        try await settle(300)
        XCTAssertNil(feed.rendition(for: "drop.jpg"))
    }

    func testAnInflightDecodeIsAdoptedAgainWhenTheFileIsLoadedAgain() async {
        let reader = FakeRenditionReader()
        reader.onDisk("keep.jpg", image: FakePicture.make(), ratio: 1)
        reader.holdDecode()
        let feed = ImageFeed(reader: reader)
        feed.load("keep.jpg")
        await waitUntil { reader.decodeCalls == ["keep.jpg"] }
        feed.retain(only: [])
        feed.load("keep.jpg")
        reader.releaseDecode()
        await waitUntil { feed.rendition(for: "keep.jpg") != nil }
        XCTAssertEqual(reader.decodeCalls, ["keep.jpg"])
    }

    func testAnAlreadyPublishedRenditionIsNeverDecodedAgain() async {
        let reader = FakeRenditionReader()
        reader.onDisk("keep.jpg", image: FakePicture.make(), ratio: 1)
        let feed = ImageFeed(reader: reader)
        feed.load("keep.jpg")
        await waitUntil { feed.rendition(for: "keep.jpg") != nil }
        feed.load("keep.jpg")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(reader.decodeCalls, ["keep.jpg"])
    }

    func testACachedBitmapWithoutACachedRatioAsksTheHeader() async {
        let reader = FakeRenditionReader()
        reader.onDisk("cached.jpg", image: FakePicture.make(), ratio: 1.75)
        reader.cacheImageOnly("cached.jpg", image: FakePicture.make())
        let feed = ImageFeed(reader: reader)
        feed.load("cached.jpg")
        await waitUntil { feed.rendition(for: "cached.jpg") != nil }
        XCTAssertEqual(feed.rendition(for: "cached.jpg")?.ratio ?? 0, 1.75, accuracy: 0.001)
        XCTAssertTrue(reader.decodeCalls.isEmpty)
        XCTAssertEqual(reader.headerReads, ["cached.jpg"])
    }

    func testForgettingAnInflightDecodeRevokesTheLateResult() async {
        let reader = FakeRenditionReader()
        reader.onDisk("drop.jpg", image: FakePicture.make(), ratio: 1)
        reader.holdDecode()
        let feed = ImageFeed(reader: reader)
        feed.load("drop.jpg")
        await waitUntil { reader.decodeCalls == ["drop.jpg"] }
        feed.forget("drop.jpg")
        reader.releaseDecode()
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(feed.rendition(for: "drop.jpg"))
    }
}
