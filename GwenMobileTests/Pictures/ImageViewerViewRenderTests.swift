@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

private final class CardViewerReader: ViewerImageReading, @unchecked Sendable {
    private let images: [String: UIImage]

    init(_ images: [String: UIImage]) {
        self.images = images
    }

    func viewerImage(named file: String) -> UIImage? {
        images[file]
    }
}

@MainActor
final class ImageViewerViewRenderTests: GwenTestCase {
    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
    }

    func testTheViewerDrawsEveryPageState() async throws {
        let reader = CardViewerReader(["a.jpg": image(), "c.jpg": image()])
        let target = try XCTUnwrap(ImagePreviewTarget(tappedFile: "b.jpg",
                                                      files: ["a.jpg", "b.jpg", "c.jpg"]))
        let controller = mountView(ImageViewerView(target: target, reader: reader),
                                   size: CGSize(width: 390, height: 800))
        try await settleHosted(controller, milliseconds: 500)
        XCTAssertNotNil(controller.view.window)
    }

    func testTheViewerDrawsForASingleFile() async throws {
        let reader = CardViewerReader(["only.jpg": image()])
        let target = try XCTUnwrap(ImagePreviewTarget(tappedFile: "only.jpg", files: ["only.jpg"]))
        let controller = mountView(ImageViewerView(target: target, reader: reader),
                                   size: CGSize(width: 390, height: 800))
        try await settleHosted(controller, milliseconds: 300)
        XCTAssertNotNil(controller.view.window)
    }
}
