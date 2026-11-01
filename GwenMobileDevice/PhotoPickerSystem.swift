@testable import GwenMobileFeatureCore
import GwenMobileKit
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class PhotosPickerItemLoader: PickedItem {
    private let item: PhotosPickerItem
    private(set) var byteCount = 0

    init(_ item: PhotosPickerItem) {
        self.item = item
    }

    func image(maxPixel: CGFloat) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        byteCount = data.count
        return try? await Offload.run {
            MediaStore.thumbnail(data, maxPixel: maxPixel)
        }
    }
}

enum PhotoPickerSystem {
    @MainActor static func install() {
        PhotoPickerPort.makeItem = { PhotosPickerItemLoader($0) }
    }
}
