import XCTest
@testable import GwenMobile

@MainActor
final class StorageTests: XCTestCase {
    private func tempDocuments() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

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

    func testStoreImageDataKeepsSmallPayloadByteForByte() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let payload = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let name = try XCTUnwrap(media.storeImageData(payload))
        XCTAssertTrue(name.hasPrefix("img_"))
        XCTAssertEqual(media.data(for: Attachment(file: name)), payload)
        media.removeImage(named: name)
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
        media.moveImagesToTrash([name])
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
}
