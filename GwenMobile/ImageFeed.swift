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

    init(reader: ImageRenditionReading) {
        self.reader = reader
    }

    func rendition(for file: String) -> ImageRendition? { renditions[file] }

    func load(_ file: String) {
        guard renditions[file] == nil, !inflight.contains(file) else { return }
        if let cached = reader.cachedDisplayImage(named: file),
           let ratio = reader.cachedDisplayRatio(named: file) {
            renditions[file] = ImageRendition(image: cached, ratio: ratio)
            return
        }
        inflight.insert(file)
        let reader = self.reader
        Task.detached(priority: .userInitiated) {
            let image = reader.decodedDisplayImage(named: file)
            let ratio = reader.displayRatio(named: file)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inflight.remove(file)
                guard let image, self.renditions[file] == nil else { return }
                self.renditions[file] = ImageRendition(image: image, ratio: ratio)
            }
        }
    }

    func forget(_ file: String) { renditions[file] = nil }
}
