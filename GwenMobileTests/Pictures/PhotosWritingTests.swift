@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import UIKit
import XCTest
import GwenMobileKit

final class FakePhotoLibrary: PhotoLibraryAdding, @unchecked Sendable {
    struct Snapshot: Equatable {
        var allowed = true
        var accepts = Int.max
        var written = 0
    }

    private let state = LockedValue(Snapshot())

    var snapshot: Snapshot { state.current }

    func refuseAccess() { state.mutate { $0.allowed = false } }
    func accept(_ count: Int) { state.mutate { $0.accepts = count } }

    func allowsWriting() async -> Bool { state.current.allowed }

    func add(_ image: UIImage) async -> Bool {
        state.mutate { box in
            guard box.written < box.accepts else { return false }
            box.written += 1
            return true
        }
    }
}

@MainActor
final class PhotosWritingTests: GwenTestCase {
    private var three: [UIImage] { [FakePicture.make(), FakePicture.make(), FakePicture.make()] }

    func testEveryPictureIsWrittenInItsOwnTransaction() async {
        let library = FakePhotoLibrary()
        var seen: [Int] = []
        let outcome = await PhotoLibraryWriter(library: library).write(three) { seen.append($0) }
        XCTAssertEqual(outcome, .saved(3))
        XCTAssertEqual(seen, [1, 2, 3], "die Leiste braucht einen Schritt pro Bild")
        XCTAssertEqual(library.snapshot.written, 3)
    }

    func testADeniedLibraryStopsBeforeWritingAnything() async {
        let library = FakePhotoLibrary()
        library.refuseAccess()
        let outcome = await PhotoLibraryWriter(library: library).write(three)
        XCTAssertEqual(outcome, .denied)
        XCTAssertEqual(library.snapshot.written, 0)
    }

    func testNothingToWriteIsAFailureAndNotASilentSuccess() async {
        let outcome = await PhotoLibraryWriter(library: FakePhotoLibrary()).write([])
        XCTAssertEqual(outcome, .failed)
    }

    func testAPartialRunReportsWhatActuallyLanded() async {
        let library = FakePhotoLibrary()
        library.accept(2)
        var seen: [Int] = []
        let outcome = await PhotoLibraryWriter(library: library).write(three) { seen.append($0) }
        XCTAssertEqual(outcome, .saved(2))
        XCTAssertEqual(seen, [1, 2])
    }

    func testARefusedFirstPictureIsReportedAsFailure() async {
        let library = FakePhotoLibrary()
        library.accept(0)
        let outcome = await PhotoLibraryWriter(library: library).write(three)
        XCTAssertEqual(outcome, .failed)
    }

    func testOnlyAWriteThatLandedEndsTheSelection() {
        XCTAssertTrue(PhotosWriteOutcome.saved(2).didWrite)
        XCTAssertFalse(PhotosWriteOutcome.saved(0).didWrite)
        XCTAssertFalse(PhotosWriteOutcome.denied.didWrite)
        XCTAssertFalse(PhotosWriteOutcome.failed.didWrite)
    }

    func testTheNoticeLinesMatchWhatTheLibraryAnswered() {
        XCTAssertEqual(Bubble.savedLine(.saved(4)), "✔ 4 images saved to Photos")
        XCTAssertEqual(Bubble.savedLine(.saved(1)), L.t("image_saved"))
        XCTAssertEqual(Bubble.savedLine(.denied), L.t("photos_not_allowed"))
        XCTAssertEqual(Bubble.savedLine(.failed), L.t("save_failed"))
    }
}
