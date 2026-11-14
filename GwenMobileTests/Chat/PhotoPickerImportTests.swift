@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI
import UIKit
import XCTest

@MainActor
private final class FakePickedItem: PickedItem {
    let imageResult: UIImage?
    var byteCount: Int { 42 }

    init(_ image: UIImage?) { imageResult = image }

    func image(maxPixel: CGFloat) async -> UIImage? { imageResult }
}

@MainActor
final class PhotoPickerImportTests: GwenTestCase {
    private func picture() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    func testTheImporterCollectsLoadableImages() async {
        let collected = LockedValue<[PendingPicture]>([])
        let importer = PhotoPickerImporter { collected.set($0) }
        await importer.importPicked([FakePickedItem(picture()), FakePickedItem(nil)])
        XCTAssertEqual(collected.current.count, 1)
        XCTAssertEqual(collected.current.first?.image.size.width, 4)
        let stub = StubPickedItem()
        XCTAssertEqual(stub.byteCount, 0)
        let none = await stub.image(maxPixel: 10)
        XCTAssertNil(none)
    }
}
