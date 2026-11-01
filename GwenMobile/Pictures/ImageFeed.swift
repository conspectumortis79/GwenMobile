import GwenMobileKit
import UIKit

struct ImageRendition {
    let image: UIImage
    let ratio: CGFloat
}

protocol ImageRenditionReading: Sendable {
    func cachedDisplayImage(named file: String) -> UIImage?
    func decodedDisplayImage(named file: String) -> UIImage?
    func cachedDisplayRatio(named file: String) -> CGFloat?
    func displayRatio(named file: String) -> CGFloat
}

extension MediaStore: ImageRenditionReading {}

@MainActor
final class ImageFeed: ObservableObject {
    @Published private(set) var renditions: [String: ImageRendition] = [:]

    private let reader: ImageRenditionReading
    private var inflight: Set<String> = []
    private var revoked: Set<String> = []

    init(reader: ImageRenditionReading) {
        self.reader = reader
    }

    func rendition(for file: String) -> ImageRendition? { renditions[file] }

    func ratio(for file: String) -> CGFloat {
        renditions[file]?.ratio ?? reader.cachedDisplayRatio(named: file) ?? reader.displayRatio(named: file)
    }

    func load(_ file: String) {
        guard renditions[file] == nil else { return }
        if inflight.contains(file) {
            revoked.remove(file)
            return
        }
        inflight.insert(file)
        if let cached = reader.cachedDisplayImage(named: file) {
            let ratio = reader.cachedDisplayRatio(named: file) ?? reader.displayRatio(named: file)
            Task { @MainActor [weak self] in
                self?.publish(file, image: cached, ratio: ratio)
            }
            return
        }
        let reader = self.reader
        Task.detached(priority: .userInitiated) {
            let image = reader.decodedDisplayImage(named: file)
            let ratio = reader.displayRatio(named: file)
            await MainActor.run { [weak self] in
                self?.publish(file, image: image, ratio: ratio)
            }
        }
    }

    func forget(_ file: String) {
        renditions[file] = nil
        if inflight.contains(file) { revoked.insert(file) }
    }

    func retain(only files: Set<String>) {
        let stale = inflight.filter { !files.contains($0) }
        let dropped = renditions.keys.contains(where: { !files.contains($0) })
        guard dropped || !stale.isEmpty else { return }
        if dropped { renditions = renditions.filter { files.contains($0.key) } }
        revoked.formUnion(stale)
    }

    private func publish(_ file: String, image: UIImage?, ratio: CGFloat) {
        inflight.remove(file)
        let wasRevoked = revoked.remove(file) != nil
        guard let image, renditions[file] == nil, !wasRevoked else { return }
        renditions[file] = ImageRendition(image: image, ratio: ratio)
    }
}
