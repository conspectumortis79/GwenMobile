@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

private struct DownloadFailed: Error {}

private final class RefusedPictures: ImageGenerating, @unchecked Sendable {
    let calls = LockedValue(0)

    func generate(baseURL: String, key: String, model: String, prompt: String,
                  inputImages: [Data], isEdit: Bool) async throws -> [GeneratedPicture] {
        calls.mutate { $0 += 1 }
        throw APIError(message: "content policy", status: 400)
    }
}

private final class ThrottledPictures: ImageGenerating, @unchecked Sendable {
    private let picture: GeneratedPicture
    private let refusals: LockedValue<Int>
    private let asked = LockedValue(0)

    init(refusals: Int, picture: GeneratedPicture) {
        self.refusals = LockedValue(refusals)
        self.picture = picture
    }

    var calls: Int { asked.current }

    func generate(baseURL: String, key: String, model: String, prompt: String,
                  inputImages: [Data], isEdit: Bool) async throws -> [GeneratedPicture] {
        asked.mutate { $0 += 1 }
        let refuse = refusals.mutate { value -> Bool in
            guard value > 0 else { return false }
            value -= 1
            return true
        }
        guard !refuse else { throw APIError(message: "Throttling.BurstRate", status: 429) }
        return [picture]
    }
}

private final class CreditsInFlightPictures: ImageGenerating, @unchecked Sendable {
    private let picture: GeneratedPicture
    private let refusals: LockedValue<Int>
    private let asked = LockedValue(0)

    init(refusals: Int, picture: GeneratedPicture) {
        self.refusals = LockedValue(refusals)
        self.picture = picture
    }

    var calls: Int { asked.current }

    func generate(baseURL: String, key: String, model: String, prompt: String,
                  inputImages: [Data], isEdit: Bool) async throws -> [GeneratedPicture] {
        asked.mutate { $0 += 1 }
        let refuse = refusals.mutate { value -> Bool in
            guard value > 0 else { return false }
            value -= 1
            return true
        }
        guard !refuse else {
            throw APIError(message: "This request would exceed your available credits given your "
                           + "current in-flight requests. Retry after in-flight requests complete.",
                           status: 402)
        }
        return [picture]
    }
}

@MainActor
final class ImageDeliveryTests: XCTestCase {
    private let pictureURLs = [URL(string: "https://example.com/bild-1.jpg")!,
                               URL(string: "https://example.com/bild-2.jpg")!]

    private func makeMedia() -> MediaStore {
        let media = MediaStore(paths: StoragePaths(documents: tempDocuments()))
        media.prepareDirectories()
        return media
    }

    func testAPictureBlockedByInflightCreditsIsAskedAgain() async throws {
        let media = makeMedia()
        let png = try XCTUnwrap(FakePicture.make().pngData())
        let backend = CreditsInFlightPictures(refusals: 1, picture: .inline(png))
        let delivery = ImageDelivery(media: media, backend: backend)
        let previous = ImageDelivery.inflightRetrySeconds
        ImageDelivery.inflightRetrySeconds = 0
        defer { ImageDelivery.inflightRetrySeconds = previous }
        let attachments = try await delivery.makePicture(baseURL: "https://q.test", key: "k",
                                                        model: "m", prompt: "p")
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(backend.calls, 2, "ein Bild am Guthaben-Limit wird nach den laufenden Anfragen wiederholt")
        let limit = APIError(message: "This request would exceed your available credits given your "
                            + "current in-flight requests. Retry after in-flight requests complete.",
                            status: 402)
        XCTAssertTrue(limit.isInflightCreditLimit)
        XCTAssertFalse(limit.isRateLimited)
        XCTAssertFalse(APIError(message: "guthaben leer", status: 402).isInflightCreditLimit)
        XCTAssertFalse(APIError(message: "in-flight", status: 429).isInflightCreditLimit)
    }

    func testAPictureThatIsThrottledIsAskedAgain() async throws {
        let media = makeMedia()
        let png = try XCTUnwrap(FakePicture.make().pngData())
        let backend = ThrottledPictures(refusals: 1, picture: .inline(png))
        let delivery = ImageDelivery(media: media, backend: backend)
        let attachments = try await delivery.makePicture(baseURL: "https://q.test", key: "k",
                                                        model: "m", prompt: "p")
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(backend.calls, 2, "ein gedrosseltes Bild wird wiederholt")
    }

    func testAPictureErrorThatIsNoThrottlingIsHandedOnAtOnce() async throws {
        let media = makeMedia()
        let backend = RefusedPictures()
        let delivery = ImageDelivery(media: media, backend: backend)
        do {
            _ = try await delivery.makePicture(baseURL: "https://q.test", key: "k", model: "m", prompt: "p")
            XCTFail("erwartet Fehler")
        } catch let error as APIError {
            XCTAssertFalse(error.isRateLimited)
        }
        XCTAssertEqual(backend.calls.current, 1, "ein anderer Fehler wird nicht wiederholt")
    }

    func testAPictureThatStaysThrottledEndsWithTheProvidersAnswer() async throws {
        let media = makeMedia()
        let png = try XCTUnwrap(FakePicture.make().pngData())
        let backend = ThrottledPictures(refusals: 99, picture: .inline(png))
        let delivery = ImageDelivery(media: media, backend: backend)
        do {
            _ = try await delivery.makePicture(baseURL: "https://q.test", key: "k", model: "m", prompt: "p")
            XCTFail("erwartet Fehler")
        } catch let error as APIError {
            XCTAssertTrue(error.isRateLimited)
        }
        XCTAssertEqual(backend.calls, RateLimitRetry.attempts)
    }

    func testStoreKeepsEveryPictureWhenAllDownloadsSucceed() async throws {
        let media = makeMedia()
        let attachments = try await ImageDelivery(media: media, backend: DashScopeImageBackend()).store(pictureURLs.map(GeneratedPicture.remote)) { _ in Data([8, 8]) }
        XCTAssertEqual(attachments.count, 2)
        XCTAssertEqual(Set(media.fileNames()), Set(attachments.map(\.file)))
    }

    func testStoreRemovesAlreadyWrittenPicturesWhenALaterDownloadFails() async throws {
        let media = makeMedia()
        var served = 0
        var thrown: Error?
        do {
            _ = try await ImageDelivery(media: media, backend: DashScopeImageBackend()).store(pictureURLs.map(GeneratedPicture.remote)) { _ in
                served += 1
                if served == 2 {
                    XCTAssertEqual(media.fileNames().count, 1)
                    throw DownloadFailed()
                }
                return Data([8, 8])
            }
        } catch {
            thrown = error
        }
        XCTAssertEqual(served, 2)
        XCTAssertTrue(thrown is DownloadFailed)
        XCTAssertTrue(media.fileNames().isEmpty)
    }

    func testStoreFailsBeforeWritingWhenTheFirstDownloadFails() async throws {
        let media = makeMedia()
        var thrown: Error?
        do {
            _ = try await ImageDelivery(media: media, backend: DashScopeImageBackend()).store(pictureURLs.map(GeneratedPicture.remote)) { _ in throw DownloadFailed() }
        } catch {
            thrown = error
        }
        XCTAssertTrue(thrown is DownloadFailed)
        XCTAssertTrue(media.fileNames().isEmpty)
    }
}
