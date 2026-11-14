import Photos
import UIKit

enum PhotosWriteOutcome: Equatable {
    case saved(Int)
    case denied
    case failed

    var didWrite: Bool {
        if case .saved(let count) = self { return count > 0 }
        return false
    }
}

protocol PhotoLibraryAdding: AnyObject, Sendable {
    func allowsWriting() async -> Bool
    func add(_ image: UIImage) async -> Bool
}

final class SystemPhotoLibrary: PhotoLibraryAdding, @unchecked Sendable {
    nonisolated(unsafe) static var authorization: @Sendable () async -> PHAuthorizationStatus = {
        await authorizationDefault()
    }

    nonisolated(unsafe) static var performChanges: @Sendable (@escaping @Sendable () -> Void) async -> Bool = {
        changes in
        await performChangesDefault(changes)
    }

    nonisolated static func authorizationDefault() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }

    nonisolated static func performChangesDefault(_ changes: @escaping @Sendable () -> Void) async -> Bool {
        await withCheckedContinuation { (resume: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, _ in
                resume.resume(returning: success)
            }
        }
    }

    func allowsWriting() async -> Bool {
        let status = await Self.authorization()
        return status == .authorized || status == .limited
    }

    func add(_ image: UIImage) async -> Bool {
        await Self.performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}

@MainActor
final class PhotoLibraryWriter {
    private let library: PhotoLibraryAdding

    init(library: PhotoLibraryAdding = SystemPhotoLibrary()) {
        self.library = library
    }

    func write(_ images: [UIImage],
               progressed: @escaping @MainActor (Int) -> Void = { _ in }) async -> PhotosWriteOutcome {
        guard !images.isEmpty else { return .failed }
        guard await library.allowsWriting() else { return .denied }
        var done = 0
        for image in images {
            guard await library.add(image) else { break }
            done += 1
            progressed(done)
        }
        guard done > 0 else { return .failed }
        return .saved(done)
    }
}
