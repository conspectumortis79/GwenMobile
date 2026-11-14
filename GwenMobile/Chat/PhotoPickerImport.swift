import GwenMobileKit
import PhotosUI
import SwiftUI
import UIKit

@MainActor
protocol PickedItem {
    var byteCount: Int { get }
    func image(maxPixel: CGFloat) async -> UIImage?
}

@MainActor
struct StubPickedItem: PickedItem {
    var byteCount: Int { 0 }
    func image(maxPixel: CGFloat) async -> UIImage? { nil }
}

@MainActor
enum PhotoPickerPort {
    nonisolated(unsafe) static var makeItem: (@MainActor (PhotosPickerItem) -> any PickedItem)?
}

@MainActor
struct PhotoPickerImporter {
    let onPicked: ([PendingPicture]) -> Void

    func importPicked(_ items: [any PickedItem]) async {
        var picked: [PendingPicture] = []
        for item in items {
            if let img = await item.image(maxPixel: ImagePolicy.uploadMaxPixel) {
                flowMark("PICKER decoded bytes=\(item.byteCount) ok=true")
                picked.append(PendingPicture(image: img, file: nil))
            }
        }
        onPicked(picked)
    }
}
