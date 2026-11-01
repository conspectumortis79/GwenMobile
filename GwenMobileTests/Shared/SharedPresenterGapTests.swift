@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class SharedPresenterGapTests: GwenTestCase {
    func testThePresenterPresentsAndShares() throws {
        let window = hostWindow(Text("Host"))
        addTeardownBlock { window?.isHidden = true }
        print("PROBE state=\(UIApplication.shared.applicationState.rawValue) scenes=\(UIApplication.shared.connectedScenes.count)")
        guard let host = Presenter.topViewController else {
            print("PROBE no top view controller")
            return
        }
        Presenter.present(UIViewController(), from: host)
        XCTAssertNotNil(Presenter.topViewController)
        XCTAssertTrue(Presenter.presentIfPossible(UIViewController()))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("gap-share.txt")
        try Data("Inhalt".utf8).write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        try Presenter.share(url: file)
        try Presenter.share(urls: [file])
        XCTAssertThrowsError(try Presenter.share(urls: []))
    }

    func testTheShareSessionCloser() {
        let host = UIViewController()
        let closer = ShareChainCloser(host: host)
        closer.close()
        let session = ShareSession(closer: closer, policy: ShareHandoverPolicy())
        session.noteHandover(nil)
        session.noteHandover(.airDrop)
        session.noteReturnedToForeground()
        session.noteSystemCompletion()
        let item = session.itemSource(for: URL(fileURLWithPath: "/tmp/gap.txt"))
        XCTAssertNotNil(item)
        XCTAssertFalse(ShareHandoverPolicy().closesTheSheet(on: nil))
        XCTAssertTrue(ShareHandoverPolicy().closesTheSheet(on: .airDrop))
    }

    func testTheUrlOpenerAndCellularDialer() async {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let opened = await SystemURLOpener().open(URL(string: "tel:0123456789")!)
        XCTAssertFalse(opened)
        if let dialer = CellularDialerFactory.make() {
            let start = await dialer.place(DialNumber("030123456")!)
            _ = start
        }
    }
}

@MainActor
extension SharedPresenterGapTests {
    func testThePresenterOverridePresentsSharesAndCloses() throws {
        let window = hostWindow(Text("Host"))
        addTeardownBlock { window?.isHidden = true }
        let host = try XCTUnwrap(window?.rootViewController)
        Presenter.hostOverride = host
        defer { Presenter.hostOverride = nil }
        XCTAssertNotNil(Presenter.topViewController)
        let modal = UIViewController()
        Presenter.present(modal, from: host)
        XCTAssertNotNil(Presenter.topViewController)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("gap-share-2.txt")
        try Data("Inhalt".utf8).write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        try Presenter.share(url: file)
        try Presenter.share(urls: [file])
        XCTAssertThrowsError(try Presenter.share(urls: []))
        XCTAssertTrue(Presenter.presentIfPossible(UIViewController()))
    }

    func testTheShareSessionNotePaths() {
        let host = UIViewController()
        let presenter = UIViewController()
        host.addChild(presenter)
        let closer = ShareChainCloser(host: host)
        let session = ShareSession(closer: closer, policy: ShareHandoverPolicy(closesOnHandover: [.airDrop]))
        session.noteHandover(nil)
        session.noteHandover(.airDrop)
        session.noteReturnedToForeground()
        session.noteSystemCompletion()
        session.noteSystemCompletion()
        let source = session.itemSource(for: URL(fileURLWithPath: "/tmp/gap.txt"))
        XCTAssertEqual(source.activityViewControllerPlaceholderItem(UIActivityViewController(activityItems: [],
                                                                                             applicationActivities: nil)) as? URL,
                       URL(fileURLWithPath: "/tmp/gap.txt"))
        _ = source.activityViewController(UIActivityViewController(activityItems: [],
                                                                   applicationActivities: nil),
                                          itemForActivityType: .airDrop)
    }
}
