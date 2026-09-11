import UIKit

protocol ViewerImageReading: Sendable {
    func viewerImage(named file: String) -> UIImage?
}

extension MediaStore: ViewerImageReading {
    func viewerImage(named file: String) -> UIImage? {
        guard let data = data(named: file) else { return nil }
        return Self.thumbnail(data, maxPixel: ImagePolicy.viewerMaxPixel)
    }
}

@MainActor
final class ImageViewerModel: ObservableObject {
    enum Page: Equatable {
        case loading
        case ready(UIImage)
        case unavailable
    }

    let files: [String]
    @Published private(set) var pages: [Int: Page] = [:]

    private let reader: ViewerImageReading

    init(files: [String], reader: ViewerImageReading) {
        self.files = files
        self.reader = reader
    }

    func page(_ index: Int) -> Page {
        guard files.indices.contains(index) else { return .unavailable }
        return pages[index] ?? .loading
    }

    func load(_ index: Int) {
        guard files.indices.contains(index), pages[index] == nil else { return }
        pages[index] = .loading
        let file = files[index]
        let reader = self.reader
        Task.detached(priority: .userInitiated) {
            let image = reader.viewerImage(named: file)
            await MainActor.run { [weak self] in
                guard let self, case .loading? = self.pages[index] else { return }
                self.pages[index] = image.map(Page.ready) ?? .unavailable
            }
        }
    }
}
