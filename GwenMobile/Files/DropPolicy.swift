import GwenMobileKit
import Foundation

enum DroppedItem: Equatable {
    case picture
    case document(FileKind)
}

enum DropPolicy {
    static let pictureExtensions: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif"]

    static func item(forFileNamed name: String) -> DroppedItem? {
        let ext = (name as NSString).pathExtension.lowercased()
        if pictureExtensions.contains(ext) { return .picture }
        guard let kind = FileKind(filename: name) else { return nil }
        return .document(kind)
    }
}
