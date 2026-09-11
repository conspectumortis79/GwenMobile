import XCTest
import UIKit
@testable import GwenMobile

private enum FakePicture {
    static func make(_ size: CGSize = CGSize(width: 40, height: 20)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private final class FakeViewerReader: ViewerImageReading, @unchecked Sendable {
    private let images: [String: UIImage]
    var recorded: [String] = []

    init(_ images: [String: UIImage]) { self.images = images }

    var requests: [String] { recorded }

    func viewerImage(named file: String) -> UIImage? {
        recorded.append(file)
        return images[file]
    }
}

@MainActor
final class ImageViewerTests: XCTestCase {
    private let viewerPolicy = ZoomPolicy.viewer

    func testTargetKeepsEveryPictureOfTheMessageAndStartsAtTheTappedOne() {
        let message = ChatMessage(role: .assistant, text: "ok",
                                  images: [Attachment(file: "a.jpg")],
                                  outImages: [Attachment(file: "b.jpg"), Attachment(file: "c.jpg")])
        let target = ImagePreviewTarget(tappedFile: "b.jpg", files: message.imageFiles)
        XCTAssertEqual(target?.files, ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertEqual(target?.startIndex, 1)
    }

    func testTargetRefusesAPictureThatIsNotPartOfTheMessage() {
        XCTAssertNil(ImagePreviewTarget(tappedFile: "x.jpg", files: ["a.jpg", "b.jpg"]))
        XCTAssertNil(ImagePreviewTarget(tappedFile: "a.jpg", files: []))
    }

    func testTargetIdentityFollowsThePictureListAndTheStartIndex() {
        let first = ImagePreviewTarget(tappedFile: "a.jpg", files: ["a.jpg", "b.jpg"])
        let same = ImagePreviewTarget(tappedFile: "a.jpg", files: ["a.jpg", "b.jpg"])
        let other = ImagePreviewTarget(tappedFile: "b.jpg", files: ["a.jpg", "b.jpg"])
        XCTAssertEqual(first?.id, same?.id)
        XCTAssertNotEqual(first?.id, other?.id)
    }

    func testMessageWithoutPicturesHasNothingToPreview() {
        XCTAssertEqual(ChatMessage(role: .user, text: "hi").imageFiles, [])
    }

    func testFitScaleIsLimitedByTheWiderAxis() {
        let geometry = ZoomGeometry(container: CGSize(width: 390, height: 844),
                                    image: CGSize(width: 1568, height: 900), policy: viewerPolicy)
        XCTAssertEqual(geometry.fitScale, 390 / 1568, accuracy: 0.0001)
    }

    func testFitScaleFillsTheViewerWithASmallPicture() {
        let geometry = ZoomGeometry(container: CGSize(width: 400, height: 400),
                                    image: CGSize(width: 100, height: 200), policy: viewerPolicy)
        XCTAssertEqual(geometry.fitScale, 2, accuracy: 0.0001)
    }

    func testDetailAndMaxScaleRideOnTopOfTheFitScale() {
        let geometry = ZoomGeometry(container: CGSize(width: 300, height: 300),
                                    image: CGSize(width: 600, height: 300),
                                    policy: ZoomPolicy(detailFactor: 2, maxFactor: 5))
        XCTAssertEqual(geometry.fitScale, 0.5, accuracy: 0.0001)
        XCTAssertEqual(geometry.detailScale, 1.0, accuracy: 0.0001)
        XCTAssertEqual(geometry.maxScale, 2.5, accuracy: 0.0001)
    }

    func testMaxScaleNeverStaysBelowTheDetailScale() {
        let geometry = ZoomGeometry(container: CGSize(width: 500, height: 500),
                                    image: CGSize(width: 500, height: 500),
                                    policy: ZoomPolicy(detailFactor: 3, maxFactor: 1))
        XCTAssertEqual(geometry.detailScale, 3, accuracy: 0.0001)
        XCTAssertEqual(geometry.maxScale, 3, accuracy: 0.0001)
    }

    func testDegenerateGeometryFallsBackToUnscaled() {
        let empty = ZoomGeometry(container: .zero, image: .zero, policy: viewerPolicy)
        XCTAssertEqual(empty.fitScale, 1)
        XCTAssertEqual(empty.detailScale, viewerPolicy.detailFactor, accuracy: 0.0001)
        let flat = ZoomGeometry(container: CGSize(width: 300, height: 0),
                                image: CGSize(width: 300, height: 300), policy: viewerPolicy)
        XCTAssertEqual(flat.fitScale, 1)
    }

    func testDoubleTapAlternatesBetweenDetailZoomAndFit() {
        let geometry = ZoomGeometry(container: CGSize(width: 390, height: 844),
                                    image: CGSize(width: 1000, height: 1000), policy: viewerPolicy)
        let detail = geometry.scaleAfterDoubleTap(current: geometry.fitScale)
        XCTAssertEqual(detail, geometry.detailScale, accuracy: 0.0001)
        XCTAssertEqual(geometry.scaleAfterDoubleTap(current: detail), geometry.fitScale, accuracy: 0.0001)
        XCTAssertEqual(geometry.scaleAfterDoubleTap(current: geometry.maxScale),
                       geometry.fitScale, accuracy: 0.0001)
        XCTAssertEqual(geometry.scaleAfterDoubleTap(current: geometry.fitScale * 1.2),
                       detail, accuracy: 0.0001)
    }

    func testCenteringOffsetOnlyAppearsWhileTheContentStaysSmallerThanTheViewer() {
        XCTAssertEqual(ZoomCentering.offset(containerExtent: 844, contentExtent: 224), 310.0, accuracy: 0.0001)
        XCTAssertEqual(ZoomCentering.offset(containerExtent: 390, contentExtent: 600), 0.0, accuracy: 0.0001)
    }

    func testViewerStartsFittedAndCentersALandscapePicture() throws {
        let scroll = makeViewer(imageSize: CGSize(width: 1568, height: 900),
                                container: CGSize(width: 390, height: 844))
        let fit: CGFloat = 390 / 1568
        XCTAssertEqual(scroll.minimumZoomScale, fit, accuracy: 0.0001)
        XCTAssertEqual(scroll.maximumZoomScale, fit * viewerPolicy.maxFactor, accuracy: 0.0001)
        XCTAssertEqual(scroll.zoomScale, fit, accuracy: 0.0001)
        let zoom = try XCTUnwrap(scroll.delegate?.viewForZooming?(in: scroll))
        XCTAssertEqual(zoom.frame.width, 390.0, accuracy: 0.5)
        XCTAssertEqual(zoom.frame.height, 900 * fit, accuracy: 0.5)
        XCTAssertEqual(zoom.frame.origin.x, 0.0, accuracy: 0.5)
        XCTAssertEqual(zoom.frame.origin.y, (844 - 900 * fit) / 2, accuracy: 0.5)
    }

    func testViewerLeavesNoGapOnTheAxisThatOverflows() throws {
        let scroll = makeViewer(imageSize: CGSize(width: 400, height: 2000),
                                container: CGSize(width: 390, height: 844))
        let fit: CGFloat = min(390 / 400, 844 / 2000)
        XCTAssertEqual(scroll.zoomScale, fit, accuracy: 0.0001)
        let zoom = try XCTUnwrap(scroll.delegate?.viewForZooming?(in: scroll))
        XCTAssertEqual(zoom.frame.height, 2000 * fit, accuracy: 0.5)
        XCTAssertEqual(zoom.frame.origin.y, 0.0, accuracy: 0.001)
    }

    func testDoubleTapOnTheViewerZoomsInAndBackOut() {
        let scroll = makeViewer(imageSize: CGSize(width: 1200, height: 1200),
                                container: CGSize(width: 300, height: 600))
        let fit = scroll.zoomScale
        scroll.handleDoubleTap(at: CGPoint(x: 150, y: 300), animated: false)
        XCTAssertEqual(scroll.zoomScale, fit * viewerPolicy.detailFactor, accuracy: 0.0001)
        scroll.handleDoubleTap(at: CGPoint(x: 150, y: 300), animated: false)
        XCTAssertEqual(scroll.zoomScale, fit, accuracy: 0.0001)
    }

    func testViewerReactsToSizeChangesOfTheContainer() {
        let scroll = makeViewer(imageSize: CGSize(width: 1000, height: 500),
                                container: CGSize(width: 300, height: 600))
        XCTAssertEqual(scroll.zoomScale, 300 / 1000, accuracy: 0.0001)
        scroll.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
        scroll.setNeedsLayout()
        scroll.layoutIfNeeded()
        XCTAssertEqual(scroll.zoomScale, 600 / 1000, accuracy: 0.0001)
        XCTAssertEqual(scroll.maximumZoomScale, (600 / 1000) * viewerPolicy.maxFactor, accuracy: 0.0001)
    }

    func testViewerRefitsAfterThePictureWasSwapped() throws {
        let scroll = makeViewer(imageSize: CGSize(width: 1000, height: 1000),
                                container: CGSize(width: 400, height: 400))
        XCTAssertEqual(scroll.zoomScale, 0.4, accuracy: 0.0001)
        scroll.apply(image: FakePicture.make(CGSize(width: 800, height: 400)))
        scroll.setNeedsLayout()
        scroll.layoutIfNeeded()
        XCTAssertEqual(scroll.zoomScale, 0.5, accuracy: 0.0001)
        let zoom = try XCTUnwrap(scroll.delegate?.viewForZooming?(in: scroll))
        XCTAssertEqual(zoom.frame.width / zoom.frame.height, 2.0, accuracy: 0.01)
    }

    func testModelResolvesStoredPicturesAndReportsMissingOnes() async throws {
        let reader = FakeViewerReader(["a.jpg": FakePicture.make()])
        let model = ImageViewerModel(files: ["a.jpg", "gone.jpg"], reader: reader)
        XCTAssertEqual(model.page(0), .loading)
        model.load(0)
        model.load(1)
        await waitUntil { model.page(0) != .loading && model.page(1) != .loading }
        guard case .ready(let image) = model.page(0) else {
            return XCTFail("Seite 0 blieb ohne Bild: \(model.page(0))")
        }
        XCTAssertEqual(image.size, CGSize(width: 40, height: 20))
        XCTAssertEqual(model.page(1), .unavailable)
        XCTAssertEqual(reader.requests.sorted(), ["a.jpg", "gone.jpg"])
        model.load(0)
        model.load(1)
        try await settle()
        XCTAssertEqual(reader.requests.count, 2)
    }

    func testModelRefusesIndexesOutsideThePictureList() {
        let model = ImageViewerModel(files: ["a.jpg"], reader: FakeViewerReader([:]))
        XCTAssertEqual(model.page(1), .unavailable)
        model.load(1)
        XCTAssertTrue(model.pages.isEmpty)
    }

    func testViewerImageReadsTheStoredFileWithoutTouchingTheBubbleCache() throws {
        let media = MediaStore(paths: StoragePaths(documents: tempDocuments()))
        media.prepareDirectories()
        let name = try XCTUnwrap(media.store(FakePicture.make(CGSize(width: 1200, height: 600))))
        let picture = try XCTUnwrap(media.viewerImage(named: name))
        XCTAssertEqual(picture.size.width, 1200.0, accuracy: 1)
        XCTAssertEqual(picture.size.height, 600.0, accuracy: 1)
        XCTAssertNil(media.cachedDisplayImage(named: name))
        XCTAssertNil(media.viewerImage(named: "missing.jpg"))
    }

    private func makeViewer(imageSize: CGSize, container: CGSize) -> ImageZoomScrollView {
        let scroll = ImageZoomScrollView(image: FakePicture.make(imageSize), policy: viewerPolicy)
        scroll.frame = CGRect(origin: .zero, size: container)
        scroll.setNeedsLayout()
        scroll.layoutIfNeeded()
        return scroll
    }
}
