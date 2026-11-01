@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import XCTest
import GwenMobileKit

@MainActor
final class ImagePagerTests: GwenTestCase {
    private func picture(_ side: CGFloat) -> UIImage { FakePicture.make(CGSize(width: side, height: side)) }

    private func host(_ pages: [ViewerPage], start: Int = 0) -> PagerHostController {
        let host = PagerHostController()
        host.loadViewIfNeeded()
        host.configure(pages: pages)
        host.turn(to: start, animated: false)
        return host
    }

    private func scrolling(_ controller: ImagePageViewController) -> ImageZoomScrollView? {
        controller.view.subviews.compactMap { $0 as? ImageZoomScrollView }.first
    }

    private func label(_ controller: ImagePageViewController) -> UILabel? {
        controller.view.subviews.compactMap { $0 as? UILabel }.first
    }

    private func spinner(_ controller: ImagePageViewController) -> UIActivityIndicatorView? {
        controller.view.subviews.compactMap { $0 as? UIActivityIndicatorView }.first
    }

    func testThePagerShowsTheWantedPictureAndItsNeighbours() {
        let pager = host([.ready(picture(300)), .ready(picture(400)), .ready(picture(500))], start: 1)
        XCTAssertEqual(pager.visibleIndex, 1)
        XCTAssertTrue(pager.isPagingEnabled)
        XCTAssertEqual(pager.pageBefore(1)?.index, 0)
        XCTAssertEqual(pager.pageAfter(1)?.index, 2)
    }

    func testTheEndsOfTheListHandOutNothingFurther() {
        let pager = host([.ready(picture(300)), .ready(picture(400))])
        XCTAssertNil(pager.pageBefore(0))
        XCTAssertNil(pager.pageAfter(1))
    }

    func testOnePictureAloneIsNeverSwipeable() {
        let pager = host([.ready(picture(300))])
        XCTAssertFalse(pager.isPagingEnabled, "für ein Bild sind zwei Richtungen zu viel")
        XCTAssertNil(pager.pageAfter(0))
    }

    func testAZoomedPictureBlocksTheSwipeAndLetsItThroughAgain() {
        let pager = host([.ready(picture(300)), .ready(picture(400))])
        guard let page = pager.pageAfter(0) else { return XCTFail("der Nachbar fehlt") }
        XCTAssertTrue(pager.isPagingEnabled)
        page.onZoomed?(true)
        XCTAssertFalse(pager.isPagingEnabled, "rein gezoomt gehört die waagerechte Geste dem Verschieben")
        page.onZoomed?(false)
        XCTAssertTrue(pager.isPagingEnabled)
    }

    func testAnIndexOutsideTheListLeavesTheShownPictureAlone() {
        let pager = host([.ready(picture(300)), .ready(picture(400))], start: 1)
        pager.turn(to: 9, animated: false)
        XCTAssertEqual(pager.visibleIndex, 1)
        pager.turn(to: -3, animated: false)
        XCTAssertEqual(pager.visibleIndex, 1)
    }

    func testARefreshKeepsTheShownPictureInPlace() {
        let replacement = picture(700)
        let pager = host([.ready(picture(300)), .ready(picture(400))], start: 1)
        pager.configure(pages: [.loading, .ready(replacement)])
        XCTAssertEqual(pager.visibleIndex, 1)
    }

    func testACompletedTurnHandsTheNewIndexToTheChatAndOpensTheGateAgain() {
        let pager = host([.ready(picture(300)), .ready(picture(400))])
        guard let neighbour = pager.pageAfter(0) else { return XCTFail("der Nachbar fehlt") }
        var turned = -1
        pager.onTurn = { seen in turned = seen }
        neighbour.onZoomed?(true)
        XCTAssertFalse(pager.isPagingEnabled, "die Meldung eines Zooms muss die Wischgeste schließen")
        pager.turnCompleted(with: neighbour)
        XCTAssertEqual(turned, 1, "ohne den Index in der Blase steht der Zähler auf dem alten Bild")
        XCTAssertTrue(pager.isPagingEnabled, "die frisch geblätterte Seite sitzt eingepasst, also wischen frei")
        XCTAssertEqual(pager.visibleIndex, 0, "der Bericht allein verschiebt nichts")
        turned = -1
        pager.turnCompleted(with: nil)
        XCTAssertEqual(turned, -1, "ein abgebrochener Wisch meldet nichts Neues")
    }

    func testATurnOntoAStillZoomedPictureKeepsTheGateClosed() {
        let zoomed = ImagePageViewController(index: 1)
        zoomed.view.frame = CGRect(origin: .zero, size: CGSize(width: 300, height: 600))
        zoomed.loadViewIfNeeded()
        zoomed.show(.ready(picture(1200)))
        zoomed.view.layoutIfNeeded()
        guard let scroll = scrolling(zoomed) else { return XCTFail("kein Blätterbetrachter") }
        scroll.handleDoubleTap(at: CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), animated: false)
        scroll.layoutIfNeeded()
        XCTAssertTrue(zoomed.isZoomedIn)
        let pager = host([.ready(picture(300)), .ready(picture(400))])
        var turned = -1
        pager.onTurn = { seen in turned = seen }
        pager.turnCompleted(with: zoomed)
        XCTAssertEqual(turned, 1)
        XCTAssertFalse(pager.isPagingEnabled, "wer rein gezoomt bleibt, blättert nicht versehentlich weiter")
    }

    func testAPageWaitsWithItsContentUntilItsViewExists() {
        let page = ImagePageViewController(index: 3)
        XCTAssertFalse(page.isViewLoaded)
        page.show(.unavailable)
        XCTAssertFalse(page.isViewLoaded, "ein Wisch-Ziel wird nicht aufgebaut, bevor es gebraucht wird")
        page.loadViewIfNeeded()
        XCTAssertEqual(label(page)?.text, L.t("image_gone"))
        XCTAssertFalse(page.isZoomedIn)
    }

    func testAReadyPageHandsThePictureToTheZoomSurface() {
        let page = ImagePageViewController(index: 0)
        page.loadViewIfNeeded()
        page.show(.ready(picture(320)))
        guard let scroll = scrolling(page) else { return XCTFail("kein Blätterbetrachter angelegt") }
        XCTAssertEqual(scroll.isHidden, false)
        let sheet = scroll.delegate?.viewForZooming?(in: scroll) as? UIImageView
        XCTAssertEqual(sheet?.image?.size, CGSize(width: 320, height: 320))
        page.show(.ready(picture(640)))
        XCTAssertEqual(page.view.subviews.compactMap { $0 as? ImageZoomScrollView }.count, 1,
                       "das nächste Bild nimmt denselben Betrachter, es entsteht kein zweites")
    }

    func testAPendingPageSpinsAndHidesTheComplaint() {
        let page = ImagePageViewController(index: 1)
        page.loadViewIfNeeded()
        page.show(.loading)
        XCTAssertEqual(spinner(page)?.isAnimating, true)
        XCTAssertEqual(label(page)?.isHidden, true)
        page.show(.unavailable)
        XCTAssertEqual(spinner(page)?.isAnimating, false)
        XCTAssertEqual(label(page)?.isHidden, false)
    }

    func testALostPictureStopsShowingTheZoomSurface() {
        let page = ImagePageViewController(index: 0)
        page.loadViewIfNeeded()
        page.show(.ready(picture(300)))
        page.show(.unavailable)
        XCTAssertEqual(scrolling(page)?.isHidden, true)
        XCTAssertEqual(label(page)?.isHidden, false)
    }

    func testTheDataSourceRefusesToInventPagesForForeignControllers() {
        let pager = host([.ready(picture(300)), .ready(picture(400))])
        let foreign = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        XCTAssertNil(pager.pageViewController(foreign, viewControllerBefore: UIViewController()))
        XCTAssertNil(pager.pageViewController(foreign, viewControllerAfter: UIViewController()))
    }

    func testTheArrowKeysStayOffUntilThePlatformAsksForThem() throws {
        let pager = host([.ready(picture(300)), .ready(picture(400))])
        XCTAssertNil(pager.keyCommands, "unter iOS darf kein Pfeiltasten-Befehl die Steuerung kreuzen")
        XCTAssertFalse(pager.canBecomeFirstResponder, "ohne Mac gehört die Tastatur niemandem weg")
        pager.arrowKeysEnabled = true
        XCTAssertEqual(try XCTUnwrap(pager.keyCommands).count, 2)
        XCTAssertTrue(pager.canBecomeFirstResponder, "nur als Erster in der Kette holt UIKit die Pfeiltasten ab")
    }

    func testTheArrowCommandsCarryBothDirectionsAndOutrankTheSystemFocusKeys() throws {
        let pager = host([.ready(picture(300)), .ready(picture(400))])
        pager.arrowKeysEnabled = true
        let commands = try XCTUnwrap(pager.keyCommands)
        XCTAssertEqual(commands.map(\.input), [UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow])
        XCTAssertEqual(commands.map(\.modifierFlags), [UIKeyModifierFlags(), UIKeyModifierFlags()])
        XCTAssertEqual(commands.map(\.wantsPriorityOverSystemBehavior), [true, true])
        XCTAssertTrue(commands.allSatisfy { ($0.discoverabilityTitle ?? "").isEmpty == false })
    }

    func testAnArrowKeyPressWalksTheBoundIndexAndRefusesToLeaveTheList() throws {
        let pages = [ViewerPage.ready(picture(300)), .ready(picture(400)), .ready(picture(500))]
        var shown = 2
        let view = ImagePagerView(pages: pages, arrowKeys: true,
                                  index: Binding(get: { shown }, set: { shown = $0 }))
        let coordinator = view.makeCoordinator()
        let pager = host(pages, start: 2)
        pager.arrowKeysEnabled = true
        pager.onStep = { step in coordinator.step(step) }
        let commands = try XCTUnwrap(pager.keyCommands)
        let retreat = try XCTUnwrap(commands[0].action)
        let advance = try XCTUnwrap(commands[1].action)

        UIApplication.shared.sendAction(advance, to: pager, from: nil, for: nil)
        XCTAssertEqual(shown, 2, "hinter dem letzten Bild ist kein weiter mehr übrig")
        UIApplication.shared.sendAction(retreat, to: pager, from: nil, for: nil)
        XCTAssertEqual(shown, 1)
        UIApplication.shared.sendAction(retreat, to: pager, from: nil, for: nil)
        XCTAssertEqual(shown, 0)
        UIApplication.shared.sendAction(retreat, to: pager, from: nil, for: nil)
        XCTAssertEqual(shown, 0, "vor dem ersten Bild hält die Liste an")
    }
}
