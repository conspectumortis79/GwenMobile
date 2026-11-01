@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class WebPagePreviewCoverageTests: GwenTestCase {
    func testThePreviewDrawsForALocalPage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("web-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("seite.html")
        try Data("<html><body><h1>Hallo</h1></body></html>".utf8).write(to: url)
        let page = CodePreviewPage(url: url)
        XCTAssertEqual(page.id, url)
        XCTAssertEqual(page.name, "seite.html")
        let controller = mountView(NavigationStack { WebPagePreview(page: page) },
                                   size: CGSize(width: 390, height: 700))
        try await settleHosted(controller, milliseconds: 500)
        XCTAssertNotNil(controller.view.window)
    }

    func testTheToolbarActionsReloadAndCloseThePreview() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("web-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("seite.html")
        try Data("<html><body><h1>Hallo</h1></body></html>".utf8).write(to: url)
        let page = CodePreviewPage(url: url)
        let controller = mountView(NavigationStack { WebPagePreview(page: page) },
                                   size: CGSize(width: 390, height: 700))
        try await settleHosted(controller, milliseconds: 500)
        let actions = TapProbe.drain()
        XCTAssertGreaterThanOrEqual(actions.count, 2)
        for action in actions { action() }
        try await settleHosted(controller, milliseconds: 500)
        XCTAssertNotNil(controller.view.window)
        XCTAssertTrue(TapProbe.drain().count >= 2)
    }
}
