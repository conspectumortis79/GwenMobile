@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class StorageTests: XCTestCase {
    private func makeMedia() -> MediaStore { MediaStore(paths: StoragePaths(documents: tempDocuments())) }

    func testPathLayout() {
        let paths = StoragePaths(documents: tempDocuments())
        XCTAssertEqual(paths.images.path, paths.support.appendingPathComponent("images").path)
        XCTAssertEqual(paths.trash.path, paths.support.appendingPathComponent(".trash").path)
        XCTAssertEqual(paths.storedImagesBeforeMove.path, paths.documents.appendingPathComponent("images").path)
        XCTAssertEqual(paths.storedTrashBeforeMove.path, paths.documents.appendingPathComponent(".trash").path)
        XCTAssertEqual(paths.answers.deletingLastPathComponent().path, paths.documents.path,
                       "exportierte Antworten bleiben sichtbar")
        XCTAssertEqual(paths.conversations.lastPathComponent, "conversations.json")
        XCTAssertEqual(paths.conversations.deletingLastPathComponent().path, paths.support.path)
        XCTAssertEqual(paths.apiKeySeed.lastPathComponent, "seed_api_key.txt")
        XCTAssertEqual(paths.image("a.jpg").lastPathComponent, "a.jpg")
        XCTAssertEqual(paths.fileText("b.pdf").path,
                       paths.files.appendingPathComponent("txt_b.pdf").path,
                      "die Sidecar-Regel wohnt nur einmal im Pfad")
    }

    func testTheHistoryNoLongerSitsInTheSharedDocumentsFolder() throws {
        let paths = StoragePaths()
        XCTAssertTrue(paths.support.path.contains("Application Support"), "\(paths.support.path)")
        XCTAssertNotEqual(paths.conversations.deletingLastPathComponent().path, paths.documents.path)
        XCTAssertEqual(paths.storedConversationsBeforeMove.deletingLastPathComponent().path,
                       paths.documents.path, "the old place stays named for the migration")
    }

    func testAnInjectedSandboxKeepsEveryPlaceInsideItself() throws {
        let dir = tempDocuments()
        let paths = StoragePaths(documents: dir)
        XCTAssertTrue(paths.support.path.hasPrefix(dir.path))
        XCTAssertTrue(paths.conversations.path.hasPrefix(dir.path))
    }

    func testDefaultPathsPointIntoTheSandbox() throws {
        let paths = StoragePaths()
        XCTAssertTrue(paths.documents.hasDirectoryPath)
        XCTAssertFalse(paths.images.path.contains("/Documents/"),
                       "Bildanate gehören nicht in den freigegebenen Ordner: \(paths.images.path)")
        XCTAssertFalse(paths.trash.path.contains("/Documents/"))
        XCTAssertTrue(paths.answers.path.contains("/Documents/"))
    }

    func testPicturesFromTheSharedDocumentsFolderMoveIntoAppStorage() throws {
        let paths = StoragePaths(documents: tempDocuments())
        let manager = FileManager.default
        try manager.createDirectory(at: paths.storedImagesBeforeMove, withIntermediateDirectories: true)
        try manager.createDirectory(at: paths.storedTrashBeforeMove, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: paths.storedImagesBeforeMove.appendingPathComponent("img_alt.jpg"))
        try Data([4]).write(to: paths.storedTrashBeforeMove.appendingPathComponent("alt.jpg"))

        let media = MediaStore(paths: paths)
        media.prepareDirectories()

        XCTAssertEqual(media.data(named: "img_alt.jpg"), Data([1, 2, 3]))
        XCTAssertTrue(manager.fileExists(atPath: paths.trash.appendingPathComponent("alt.jpg").path))
        XCTAssertFalse(manager.fileExists(atPath: paths.storedImagesBeforeMove.path))
        XCTAssertFalse(manager.fileExists(atPath: paths.storedTrashBeforeMove.path))
    }

    func testPrepareDirectoriesCreatesImagesAndTrash() {
        let media = makeMedia()
        media.prepareDirectories()
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.paths.images.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.paths.trash.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.paths.support.path),
                      "the conversation store needs its folder to be there before the first save")
    }

    func testStoredURLPointsAtTheRealFileOrNilWhenGone() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let payload = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let name = try XCTUnwrap(media.storeImageData(payload))
        let att = Attachment(file: name)
        let url = try XCTUnwrap(media.storedURL(for: att))
        XCTAssertEqual(url.path, media.paths.image(att.file).path)
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

    func testEncodedPicturesStayInsideTheUploadBudget() throws {
        let noisy = try XCTUnwrap(FakePicture.noisy(width: 1400, height: 1400))
        let data = try XCTUnwrap(MediaStore.encoded(noisy))
        XCTAssertTrue(data.count <= ImagePolicy.uploadByteBudget, "Bytes: \(data.count)")
        XCTAssertEqual([UInt8](data.prefix(2)), [0xFF, 0xD8])
    }

    func testSmallPicturesKeepTheirQualityAndTheirSize() throws {
        let small = try XCTUnwrap(FakePicture.make(CGSize(width: 40, height: 20)))
        let data = try XCTUnwrap(MediaStore.encoded(small))
        XCTAssertTrue(data.count <= ImagePolicy.uploadByteBudget)
    }

    func testStoringAPictureWritesExactlyTheBytesTheSingleEncoderProduced() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let noisy = try XCTUnwrap(FakePicture.noisy(width: 1200, height: 900))
        let encoded = try XCTUnwrap(MediaStore.encoded(noisy))
        let name = try XCTUnwrap(media.store(noisy))
        XCTAssertEqual(media.data(named: name)?.count, encoded.count)
    }

    func testImageFileNamesListsEveryStoredPicture() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let name = try XCTUnwrap(media.storeImageData(Data([2, 2])))
        XCTAssertEqual(media.fileNames(), [name])
        XCTAssertEqual(media.byteSize(of: name), 2)
        XCTAssertEqual(media.byteSize(of: "fehit.jpg"), 0)
    }

    func testAPayloadKeepsItsOwnPictureFormatInNameAndMIME() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let picture = FakePicture.make()
        let png = try XCTUnwrap(picture.pngData())
        let name = try XCTUnwrap(media.storeImageData(png))
        XCTAssertTrue(name.hasSuffix(".png"), name)
        XCTAssertEqual(media.fileNames(), [name])
        XCTAssertTrue(try XCTUnwrap(QwenAPI.dataURL(png)).hasPrefix("data:image/png;base64,"))
        let jpeg = try XCTUnwrap(picture.jpegData(compressionQuality: 0.8))
        XCTAssertTrue(try XCTUnwrap(QwenAPI.dataURL(jpeg)).hasPrefix("data:image/jpeg;base64,"))
        let stored = try XCTUnwrap(media.store(picture))
        XCTAssertTrue(stored.hasSuffix(".jpg"), stored)
    }

    func testPictureFormatIsReadFromTheBytesAndDefaultsToJPEG() {
        XCTAssertEqual(PictureFormat.of(Data([0x89, 0x50, 0x4E, 0x47, 0x0D])), .png)
        XCTAssertEqual(PictureFormat.of(Data([0xFF, 0xD8, 0xFF, 0xE0])), .jpeg)
        XCTAssertEqual(PictureFormat.of(Data([0x47, 0x49, 0x46, 0x38, 0x39])), .gif)
        XCTAssertEqual(PictureFormat.of(Data([0x52, 0x49, 0x46, 0x46, 0x10, 0x00, 0x00, 0x00,
                                             0x57, 0x45, 0x42, 0x50])), .webp)
        XCTAssertEqual(PictureFormat.of(Data()), .jpeg)
        XCTAssertEqual(PictureFormat.of(Data([9, 9, 9])).mimeType, "image/jpeg")
    }

    func testAnUnreadablePictureLeavesTheRatioCacheAlone() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let ghost = "img_geist_\(UUID().uuidString).png"
        XCTAssertEqual(media.displayRatio(named: ghost), 1, accuracy: 0.001)
        XCTAssertNil(media.cachedDisplayRatio(named: ghost),
                     "ein gelesener Wert von 1 darf nicht für alle Zeiten als Maß gelten")

        let wide = try XCTUnwrap(media.store(FakePicture.make(CGSize(width: 800, height: 200))))
        XCTAssertEqual(media.displayRatio(named: wide), 4, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(media.cachedDisplayRatio(named: wide)), 4, accuracy: 0.01)
    }

    func testDiscardingTrashedFilesLeavesTheRestOfTheTrashAlone() throws {
        let media = makeMedia()
        media.prepareDirectories()
        let first = try XCTUnwrap(media.storeImageData(Data([5])))
        let second = try XCTUnwrap(media.storeImageData(Data([6])))
        let movedFirst = media.moveImagesToTrash([first])
        let movedSecond = media.moveImagesToTrash([second])
        media.discardTrashed(movedFirst)
        XCTAssertFalse(FileManager.default.fileExists(atPath: media.paths.trashItem(movedFirst[0].trashed).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: media.paths.trash.path),
                       [movedSecond[0].trashed], "nur die eigene Ablage wird geleert")
    }

    func testAPIDataLeavesSmallPayloadUntouched() {
        let payload = Data(repeating: 7, count: ImagePolicy.uploadByteBudget - 1)
        XCTAssertEqual(try XCTUnwrap(MediaStore.apiData(payload)), payload)
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

extension StoragePaths {
    static func injectedSandbox(_ dir: URL) -> StoragePaths {
        StoragePaths(documents: dir.appendingPathComponent("Documents"),
                     support: dir.appendingPathComponent("Support"))
    }
}

final class StoragePathInjectionTests: XCTestCase {
    private func sharedFolderSetup() throws -> (paths: StoragePaths, source: URL, target: URL) {
        let documents = tempDocuments()
        let support = tempDocuments()
        let paths = StoragePaths(documents: documents, support: support)
        let source = documents.appendingPathComponent("images", isDirectory: true)
        let target = support.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data([1]).write(to: source.appendingPathComponent("img_a.jpg"))
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return (paths, source, target)
    }

    func testAnInjectedSupportFolderIsActuallyUsed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = StoragePaths.injectedSandbox(dir)
        XCTAssertEqual(paths.documents.path, dir.appendingPathComponent("Documents").path)
        XCTAssertEqual(paths.support.path, dir.appendingPathComponent("Support").path)
        XCTAssertEqual(paths.images.deletingLastPathComponent().path, paths.support.path)
        XCTAssertEqual(paths.trash.deletingLastPathComponent().path, paths.support.path)
        XCTAssertFalse(paths.answers.path.hasPrefix(paths.support.path),
                       "antworten bleiben im freigegebenen Dokumente-Ordner")
    }

    func testWithoutAnyHintEveryPlaceStaysInsideTheSandbox() {
        let paths = StoragePaths()
        XCTAssertFalse(paths.images.path.isEmpty)
        XCTAssertFalse(paths.documents.path.isEmpty)
        XCTAssertTrue(paths.conversations.path.hasPrefix(paths.support.path))
    }

    func testAFailedOldFolderRemovalKeepsTheFolder() throws {
        let documents = tempDocuments()
        let support = tempDocuments()
        let paths = StoragePaths(documents: documents, support: support)
        let images = documents.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data([1]).write(to: images.appendingPathComponent("img_alt.jpg"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: documents.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: documents.path) }
        paths.moveSharedFoldersIntoAppStorage()
        XCTAssertTrue(FileManager.default.fileExists(atPath: images.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: paths.images.appendingPathComponent("img_alt.jpg").path))
    }

    func testMovingWithTheSameFolderDoesNothing() {
        let folder = tempDocuments()
        let paths = StoragePaths(documents: folder, support: folder)
        paths.moveSharedFoldersIntoAppStorage()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("images").path))
    }

    func testWithoutASystemFolderTheTemporaryDirectoryWins() {
        let paths = StoragePaths(documents: nil, support: nil, fileManager: EmptyFileManager())
        XCTAssertEqual(paths.documents.path, FileManager.default.temporaryDirectory.path)
        XCTAssertEqual(paths.support.path, paths.documents.path)
    }

    func testAnExistingTargetStopsTheMoveAndKeepsTheSource() throws {
        let (paths, source, target) = try sharedFolderSetup()
        try Data([2]).write(to: target.appendingPathComponent("img_a.jpg"))
        paths.moveSharedFoldersIntoAppStorage()
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("img_a.jpg")), Data([2]))
    }

    func testAFailedMoveKeepsTheSourceFile() throws {
        let (paths, source, target) = try sharedFolderSetup()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: target.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path) }
        paths.moveSharedFoldersIntoAppStorage()
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: source.appendingPathComponent("img_a.jpg").path))
    }
}
