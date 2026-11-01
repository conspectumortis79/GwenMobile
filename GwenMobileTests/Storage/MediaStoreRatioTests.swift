@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class MediaStoreRatioTests: GwenTestCase {
    func testTheDisplayRatioIsMeasuredAndThenCached() throws {
        let store = scratchMediaStore()
        let name = try XCTUnwrap(store.store(FakePicture.make(CGSize(width: 80, height: 40))))
        XCTAssertEqual(store.displayRatio(named: name), 2, accuracy: 0.01)
        XCTAssertEqual(store.displayRatio(named: name), 2, accuracy: 0.01)
    }

    func testAnUnknownFileReportsTheNeutralRatio() {
        let store = scratchMediaStore()
        XCTAssertEqual(store.displayRatio(named: "img_gibt_es_nicht.jpg"), 1)
    }

    func testALargeUploadIsBroughtUnderTheBudget() throws {
        let image = try XCTUnwrap(FakePicture.noisy(width: 900, height: 900))
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        XCTAssertGreaterThan(data.count, ImagePolicy.uploadByteBudget)
        XCTAssertLessThanOrEqual(try XCTUnwrap(MediaStore.apiData(data)).count, ImagePolicy.uploadByteBudget)
    }

    func testEncodedAlwaysReturnsData() throws {
        let image = try XCTUnwrap(FakePicture.noisy(width: 2000, height: 2000))
        XCTAssertNotNil(MediaStore.encoded(image))
    }

    func testTheFormatReaderUnderstandsHeicAndShortHeads() {
        let heic = Data([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])
        XCTAssertEqual(PictureFormat.of(heic).fileExtension, "heic")
        XCTAssertEqual(PictureFormat.of(Data([0, 1])).fileExtension, "jpg")
        XCTAssertEqual(PictureFormat.of(Data([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70])).fileExtension, "jpg")
        let webp = Data([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])
        XCTAssertEqual(PictureFormat.of(webp).fileExtension, "webp")
        let gif = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        XCTAssertEqual(PictureFormat.of(gif).fileExtension, "gif")
    }

    func testEveryFormatNamesItsMimeTypeAndExtension() {
        for format in PictureFormat.allCases {
            XCTAssertTrue(format.mimeType.hasPrefix("image/"), format.rawValue)
            XCTAssertFalse(format.fileExtension.isEmpty, format.rawValue)
        }
        XCTAssertEqual(PictureFormat.jpeg.mimeType, "image/jpeg")
    }

    func testTheDisplayImageComesFromTheCacheOnTheSecondCall() throws {
        let store = scratchMediaStore()
        let name = try XCTUnwrap(store.store(FakePicture.make(CGSize(width: 60, height: 30))))
        XCTAssertNotNil(store.decodedDisplayImage(named: name))
        XCTAssertNotNil(store.decodedDisplayImage(named: name))
    }

    func testAGarbageFileHasNoDisplayImageAndNoRatio() throws {
        let store = scratchMediaStore()
        let name = try XCTUnwrap(store.storeImageData(Data([0xFF, 0xD8, 0xFF, 0xD9])))
        XCTAssertNil(store.decodedDisplayImage(named: name))
        XCTAssertEqual(store.displayRatio(named: name), 1)
    }

    func testARatioForAFileOutsideTheStoreIsMeasuredOnDemand() throws {
        let paths = StoragePaths(documents: tempDocuments())
        let store = MediaStore(paths: paths)
        store.prepareDirectories()
        let data = try XCTUnwrap(FakePicture.make(CGSize(width: 80, height: 40)).pngData())
        try data.write(to: paths.images.appendingPathComponent("img_hand.png"))
        XCTAssertEqual(store.displayRatio(named: "img_hand.png"), 2, accuracy: 0.01)
        XCTAssertEqual(store.displayRatio(named: "img_hand.png"), 2, accuracy: 0.01)
    }

    func testAnImpossibleStoreReturnsNoName() throws {
        let paths = StoragePaths(documents: tempDocuments())
        try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        try Data([0]).write(to: paths.images)
        let store = MediaStore(paths: paths)
        XCTAssertNil(store.store(FakePicture.make()))
    }

    func testAnEmptyImageCannotBeEncoded() {
        XCTAssertNil(MediaStore.encoded(UIImage()))
        XCTAssertNil(scratchMediaStore().store(UIImage()))
    }

    func testHugeGarbageIsRejectedWhenNormalisationFails() {
        let garbage = Data(repeating: 0xAB, count: 700_000)
        XCTAssertNil(MediaStore.apiData(garbage))
        let huge = Data(repeating: 0xCD, count: 5_000_000)
        XCTAssertNil(MediaStore.storableData(huge))
    }

    func testAFailedEncoderRejectsTheOversizedUpload() throws {
        let original = MediaStore.jpegData
        defer { MediaStore.jpegData = original }
        MediaStore.jpegData = { _, _ in nil }
        let image = try XCTUnwrap(FakePicture.noisy(width: 900, height: 900))
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        XCTAssertGreaterThan(data.count, ImagePolicy.uploadByteBudget)
        XCTAssertNil(MediaStore.apiData(data))
    }

    func testTheFallbackQualityStepsBringAnOversizedUploadUnderTheBudget() throws {
        let original = MediaStore.jpegData
        defer { MediaStore.jpegData = original }
        MediaStore.jpegData = { _, quality in
            quality > 0.4
                ? Data(repeating: 1, count: ImagePolicy.uploadByteBudget + 1)
                : Data(repeating: 2, count: 12)
        }
        let image = try XCTUnwrap(FakePicture.noisy(width: 900, height: 900))
        let source = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        XCTAssertGreaterThan(source.count, ImagePolicy.uploadByteBudget)
        XCTAssertEqual(try XCTUnwrap(MediaStore.apiData(source)).count, 12)
        XCTAssertEqual(try XCTUnwrap(MediaStore.encoded(image)).count, 12)
    }

    func testAnEncoderThatNeverFitsTheBudgetReturnsNoPicture() throws {
        let original = MediaStore.jpegData
        defer { MediaStore.jpegData = original }
        MediaStore.jpegData = { _, _ in Data(repeating: 0, count: ImagePolicy.uploadByteBudget + 1) }
        let image = try XCTUnwrap(FakePicture.make(CGSize(width: 80, height: 40)))
        XCTAssertNil(MediaStore.encoded(image))
    }

    func testAnOversizedUnencodableImageHasNoDataURL() throws {
        let original = MediaStore.jpegData
        defer { MediaStore.jpegData = original }
        MediaStore.jpegData = { _, _ in nil }
        let image = try XCTUnwrap(FakePicture.noisy(width: 900, height: 900))
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        XCTAssertGreaterThan(data.count, ImagePolicy.uploadByteBudget)
        XCTAssertNil(QwenAPI.dataURL(data))
    }

    func testOversizedStorableGarbageIsNotWritten() {
        let paths = temporaryPaths("media-hard-budget")
        let store = MediaStore(paths: paths)
        store.prepareDirectories()
        let huge = Data(repeating: 0xCD, count: ImagePolicy.storedByteBudget + 1)
        XCTAssertNil(store.storeImageData(huge))
        XCTAssertTrue(store.fileNames().isEmpty)
    }

    func testAColdCacheMeasuresAndStoresTheRatio() throws {
        let paths = temporaryPaths("media-ratio-cold")
        let store = MediaStore(paths: paths)
        try FileManager.default.createDirectory(at: paths.images, withIntermediateDirectories: true)
        let image = try XCTUnwrap(FakePicture.make(CGSize(width: 80, height: 40)))
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        try data.write(to: paths.images.appendingPathComponent("img_cold_cache.jpg"))
        XCTAssertNil(store.cachedDisplayRatio(named: "img_cold_cache.jpg"))
        XCTAssertEqual(store.displayRatio(named: "img_cold_cache.jpg"), 2, accuracy: 0.01)
        XCTAssertEqual(store.cachedDisplayRatio(named: "img_cold_cache.jpg") ?? 0, 2, accuracy: 0.01)
        XCTAssertEqual(store.displayRatio(named: "img_cold_cache.jpg"), 2, accuracy: 0.01)
    }
}
