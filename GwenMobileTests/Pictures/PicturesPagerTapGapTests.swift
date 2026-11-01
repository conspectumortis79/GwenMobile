@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class PicturesPagerTapGapTests: GwenTestCase {
    func testThePagerCoordinatorAndHost() {
        var index = 0
        let binding = Binding(get: { index }, set: { index = $0 })
        let view = ImagePagerView(pages: [.loading, .unavailable, .ready(FakePicture.make())],
                                  index: binding)
        let coordinator = PagerCoordinator(view)
        coordinator.turn(1)
        XCTAssertEqual(index, 1)
        coordinator.turn(1)
        coordinator.step(.back)
        XCTAssertEqual(index, 0)
        coordinator.step(.forward)
        XCTAssertEqual(index, 1)

        let host = PagerHostController()
        _ = host.view
        host.configure(pages: [.loading, .unavailable])
        XCTAssertEqual(host.pictureCount, 2)
        host.turn(to: 1, animated: false)
        _ = host.visibleIndex
        _ = host.isPagingEnabled
        host.arrowKeysEnabled = true
        _ = host.keyCommands
        _ = host.canBecomeFirstResponder
        host.beginAppearanceTransition(true, animated: false)
        host.endAppearanceTransition()
        _ = host.perform(NSSelectorFromString("stepForward"))
        _ = host.perform(NSSelectorFromString("stepBackward"))
        host.turnCompleted(with: nil)
        host.turnCompleted(with: ImagePageViewController(index: 0))
        _ = host.page(at: 9)
        _ = host.pageBefore(0)
        _ = host.pageAfter(0)
        let pager = UIPageViewController()
        _ = host.pageViewController(pager, viewControllerBefore: ImagePageViewController(index: 0))
        _ = host.pageViewController(pager, viewControllerAfter: ImagePageViewController(index: 0))
        host.pageViewController(pager, didFinishAnimating: true, previousViewControllers: [],
                                transitionCompleted: true)
        host.pageViewController(pager, didFinishAnimating: true, previousViewControllers: [],
                                transitionCompleted: false)
        _ = ImagePageViewController(coder: NSCoder())

        let page = ImagePageViewController(index: 0)
        page.show(.loading)
        _ = page.view
        page.show(.unavailable)
        page.show(.ready(FakePicture.make()))
        _ = page.isZoomedIn
    }

    func testTheGalleryTapViews() async throws {
        let probe = TapModifierProbe()
        _ = probe.mode
        probe.note([.command])
        XCTAssertEqual(probe.mode, .adding)
        probe.note([.shift])
        XCTAssertEqual(probe.mode, .range)
        probe.note([.alternate])
        XCTAssertEqual(probe.mode, .saving)
        probe.note([])
        XCTAssertEqual(probe.mode, .plain)
        let host = mountView(GalleryTapModifiers(probe: probe), size: CGSize(width: 100, height: 100))
        try await settleHosted(host, milliseconds: 100)
        let view = GalleryTapProbeView(frame: .zero)
        view.touchesBegan([], with: nil)
    }
}

@MainActor
extension PicturesPagerTapGapTests {
    func testTheGalleryActionButtonsRun() async throws {
        let picture = WebPicture(file: "eins.jpg", pageURL: "https://q.test/1",
                                 fullURL: "https://q.test/1.jpg", title: "Eins", domain: "q.test")
        let gallery = PictureGallery(query: "Bilder", pictures: [picture], shown: 1, exhausted: true)
        let selection = GallerySelection()
        let operation = GalleryOperation()
        let feed = ImageFeed(reader: MediaStore(paths: temporaryPaths("gallery-actions")))
        var opened = 0
        var saved = 0
        let view = PictureGalleryView(gallery: gallery, owner: UUID(), onOpen: { _ in opened += 1 },
                                      onOpenSource: { _ in }, onOpenOriginal: { _ in }, onMore: {},
                                      onShare: { _ in }, onSave: { _ in saved += 1 })
            .environmentObject(feed).environmentObject(selection).environmentObject(operation)
        let host = mountView(view, size: CGSize(width: 390, height: 600))
        try await settleHosted(host, milliseconds: 300)
        runProbedActions()
        try await settleHosted(host, milliseconds: 300)
        runProbedActions()
        XCTAssertGreaterThan(opened + saved, 0)
        let withoutOwner = PictureGalleryView(gallery: gallery, owner: nil, onOpen: { _ in opened += 1 },
                                              onOpenSource: { _ in }, onOpenOriginal: { _ in }, onMore: {},
                                              onShare: { _ in }, onSave: { _ in saved += 1 })
            .environmentObject(feed).environmentObject(selection).environmentObject(operation)
        let second = mountView(withoutOwner, size: CGSize(width: 390, height: 600))
        try await settleHosted(second, milliseconds: 300)
        runProbedActions()
        dismissPresentedSheets()
    }
}
