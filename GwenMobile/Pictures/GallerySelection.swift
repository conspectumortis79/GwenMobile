import GwenMobileKit
import Foundation

enum GalleryTapMode: Equatable {
    case plain
    case adding
    case range
    case saving
}

enum GalleryTapOutcome: Equatable {
    case selected
    case deselected
    case openPreview
    case saveOne
}

@MainActor
final class GallerySelection: ObservableObject {
    @Published private(set) var owner: UUID?
    @Published private(set) var files: Set<String> = []

    private var anchor: String?

    var count: Int { files.count }
    var isEmpty: Bool { files.isEmpty }
    var isPicking: Bool { owner != nil }

    func picking(_ message: UUID?) -> Bool {
        guard let owner, let message else { return false }
        return owner == message
    }

    func contains(_ file: String) -> Bool { files.contains(file) }

    func begin(owner: UUID) {
        guard !picking(owner) else { return }
        self.owner = owner
        files = []
        anchor = nil
    }

    func selectAll(_ order: [String]) {
        guard owner != nil else { return }
        files = Set(order)
        anchor = order.last
    }

    @discardableResult
    func tap(_ file: String, owner: UUID, in order: [String],
             mode: GalleryTapMode = .plain) -> GalleryTapOutcome {
        if !picking(owner) {
            guard mode != .plain else { return .openPreview }
            begin(owner: owner)
        }
        switch mode {
        case .plain, .adding:
            return toggle(file)
        case .range:
            return selectRange(file, in: order)
        case .saving:
            return .saveOne
        }
    }

    @discardableResult
    func toggle(_ file: String) -> GalleryTapOutcome {
        if files.contains(file) {
            files.remove(file)
            return .deselected
        }
        files.insert(file)
        anchor = file
        return .selected
    }

    func end() {
        owner = nil
        files = []
        anchor = nil
    }

    func pictures(in gallery: PictureGallery?) -> [WebPicture] {
        guard let gallery else { return [] }
        return gallery.pictures.filter { files.contains($0.file) }
    }

    private func selectRange(_ file: String, in order: [String]) -> GalleryTapOutcome {
        guard let edge = anchor, let from = order.firstIndex(of: edge),
              let to = order.firstIndex(of: file) else {
            files = [file]
            anchor = file
            return .selected
        }
        let span = min(from, to)...max(from, to)
        files = Set(order[span])
        anchor = edge
        return .selected
    }
}
