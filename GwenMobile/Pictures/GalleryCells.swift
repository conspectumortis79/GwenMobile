import GwenMobileKit
import Foundation

enum GalleryMoreKind: Equatable, Hashable {
    case hidden(Int)
    case nextRound(Int)

    var count: Int {
        switch self {
        case .hidden(let count), .nextRound(let count): return count
        }
    }

    var isRound: Bool {
        if case .nextRound = self { return true }
        return false
    }
}

enum GalleryCell: Identifiable, Hashable {
    case picture(WebPicture)
    case more(GalleryMoreKind)
    case placeholder(Int)
    case searching
    case endOfResults

    var id: String {
        switch self {
        case .picture(let picture): return "bild-\(picture.file)"
        case .more(.hidden(let count)): return "mehr-versteckt-\(count)"
        case .more(.nextRound(let count)): return "mehr-runde-\(count)"
        case .placeholder(let slot): return "platzhalter-\(slot)"
        case .searching: return "sucht"
        case .endOfResults: return "ende"
        }
    }
}

enum GalleryLayout {
    static func cells(_ gallery: PictureGallery, searching: Bool) -> [GalleryCell] {
        var cells: [GalleryCell] = gallery.visiblePictures.map { GalleryCell.picture($0) }
        if searching {
            cells.append(contentsOf: (0..<ImagePolicy.galleryLoadingPlaceholders)
                .map { GalleryCell.placeholder($0) })
            cells.append(.searching)
            return cells
        }
        if gallery.hiddenCount > 0 {
            cells.append(.more(.hidden(gallery.hiddenCount)))
            return cells
        }
        if !gallery.exhausted {
            cells.append(.more(.nextRound(ImagePolicy.galleryMaxStored)))
            return cells
        }
        cells.append(.endOfResults)
        return cells
    }
}
