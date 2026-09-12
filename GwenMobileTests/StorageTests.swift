import XCTest
@testable import GwenMobile

@MainActor
final class StorageTests: XCTestCase {
    private func makeMedia() -> MediaStore { MediaStore(paths: StoragePaths(documents: tempDocuments())) }

    func testPathLayout() {
        let paths = StoragePaths(documents: tempDocuments())
        XCTAssertEqual(paths.images.path, paths.documents.appendingPathComponent("images").path)
        XCTAssertEqual(paths.trash.path, paths.documents.appendingPathComponent(".trash").path)
        XCTAssertEqual(paths.conversations.lastPathComponent, "conversations.json")
        XCTAssertEqual(paths.apiKeySeed.lastPathComponent, "seed_api_key.txt")
        XCTAssertEqual(paths.image("a.jpg").lastPathComponent, "a.jpg")
        XCTAssertEqual(paths.imageURL(for: Attachment(file: "b.jpg")).path, paths.image("b.jpg").path)
    }

    func testDefaultPathsPointIntoTheSandbox() throws {
        let paths = StoragePaths()
        XCTAssertTrue(paths.documents.hasDirectoryPath)
        XCTAssertTrue(paths.images.path.contains("Documents"))
    }

    func testPrepareDirectoriesCreatesImagesAndTrash() {
        let media = makeMedia()
        media.prepareDirectories()
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.paths.images.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.paths.trash.path))
    }

    func testStoredURLPointsAtTheRealFileOrNilWhenGone() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let payload = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let name = try XCTUnwrap(media.storeImageData(payload))
        let att = Attachment(file: name)
        let url = try XCTUnwrap(media.storedURL(for: att))
        XCTAssertEqual(url.path, media.paths.imageURL(for: att).path)
        XCTAssertEqual(url.pathExtension, "jpg")
        XCTAssertEqual(try Data(contentsOf: url), payload)
        let trashed = media.moveImagesToTrash([name])
        XCTAssertEqual(trashed.count, 1)
        media.emptyTrash()
        XCTAssertNil(media.storedURL(for: att))
    }

    func testStoreImageDataKeepsSmallPayloadByteForByte() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let payload = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let name = try XCTUnwrap(media.storeImageData(payload))
        XCTAssertTrue(name.hasPrefix("img_"))
        XCTAssertEqual(media.data(for: Attachment(file: name)), payload)
        XCTAssertEqual(media.moveImagesToTrash([name]).count, 1)
        media.emptyTrash()
        XCTAssertNil(media.data(for: Attachment(file: name)))
    }

    func testDataNamedReadsTheSameFileAsAttachmentLookup() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let name = try XCTUnwrap(media.storeImageData(Data([1, 2, 3])))
        XCTAssertEqual(media.data(named: name), media.data(for: Attachment(file: name)))
    }

    func testRemoveFileMovesNothingButTrashRoundTripRestoresImage() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let name = try XCTUnwrap(media.storeImageData(Data([4, 5, 6])))
        let moved = media.moveImagesToTrash([name])
        XCTAssertEqual(moved.count, 1)
        XCTAssertNil(media.data(named: name))
        media.restoreFromTrash(moved)
        XCTAssertEqual(media.data(named: name), Data([4, 5, 6]))
    }

    func testEmptyTrashRemovesPendingFilesForGood() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let name = try XCTUnwrap(media.storeImageData(Data([1, 1])))
        _ = media.moveImagesToTrash([name])
        media.emptyTrash()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: media.paths.trash.path).isEmpty, true)
    }

    func testImageFileNamesListsOnlyStoredJpegs() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let name = try XCTUnwrap(media.storeImageData(Data([2, 2])))
        XCTAssertEqual(media.imageFileNames(), [name])
        XCTAssertEqual(media.byteSize(of: name), 2)
        XCTAssertEqual(media.byteSize(of: "fehit.jpg"), 0)
    }

    func testAPIDataLeavesSmallPayloadUntouched() {
        let payload = Data(repeating: 7, count: ImagePolicy.uploadByteBudget - 1)
        XCTAssertEqual(MediaStore.apiData(payload), payload)
    }

    func testExportImageKeepsTheExportSizeAndNeverFillsTheDisplayCache() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let name = try XCTUnwrap(media.store(FakePicture.make(CGSize(width: 2000, height: 1000))))
        let export = try XCTUnwrap(media.exportImage(named: name))
        XCTAssertEqual(export.size.width, ImagePolicy.photoExportMaxPixel, accuracy: 1)
        XCTAssertNil(media.cachedDisplayImage(named: name))
        let display = try XCTUnwrap(media.decodedDisplayImage(named: name))
        XCTAssertEqual(display.size.width, ImagePolicy.displayMaxPixel, accuracy: 1)
        XCTAssertEqual(media.cachedDisplayImage(named: name)?.size.width, display.size.width)
        XCTAssertNil(media.exportImage(named: "missing.jpg"))
    }
}
