@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class CodeBlockGapTests: GwenTestCase {
    private let block = CodeBlock(language: .html,
                                  lines: ["<!doctype html>", "<html>", "<body>Hallo</body>", "</html>"])

    private func makeActions() -> (CodeCardActions, RecordingCodePresenter, RecordingCodeExporter) {
        let paths = StoragePaths(documents: tempDocuments())
        let files = SavedCodeFiles(exporter: CodeFileExporter(paths: paths))
        let presenter = RecordingCodePresenter()
        let exporter = RecordingCodeExporter()
        return (CodeCardActions(files: files, presenter: presenter, exporter: exporter),
                presenter, exporter)
    }

    func testSmokeTheCodeCardButtonsRun() async throws {
        let (actions, presenter, exporter) = makeActions()
        let view = CodeBlockView(block: block, question: "Was ist das?", actions: actions)
        let controller = mountView(view, size: CGSize(width: 390, height: 420))
        try await settleHosted(controller, milliseconds: 250)
        for action in MirrorTap.actions(in: view.body) { action() }
        try await settleHosted(controller, milliseconds: 250)
        _ = view.body
        _ = presenter.presented
        _ = exporter.exported
        let (failingActions, failingPresenter, _) = makeActions()
        failingPresenter.failure = PresenterError.noHost
        let failing = CodeBlockView(block: block, question: nil, actions: failingActions)
        for action in MirrorTap.actions(in: failing.body) { action() }
        try await settleHosted(controller, milliseconds: 150)
        _ = failing.body
    }

    func testTheTapProbeHeaderActions() async throws {
        let (actions, _, exporter) = makeActions()
        let view = CodeBlockView(block: block, question: "Was ist das?", actions: actions)
        let controller = mountView(view, size: CGSize(width: 390, height: 420))
        try await settleHosted(controller, milliseconds: 250)
        TapProbe.reset()
        _ = view.body
        let probed = TapProbe.drain()
        XCTAssertEqual(probed.count, 4)
        for action in probed { action() }
        try await settleHosted(controller, milliseconds: 250)
        _ = view.body
        XCTAssertEqual(exporter.exported.count, 1)
        exporter.failure = PresenterError.noHost
        let failing = CodeBlockView(block: block, question: nil, actions: actions)
        let failingHost = mountView(failing, size: CGSize(width: 390, height: 420))
        try await settleHosted(failingHost, milliseconds: 250)
        TapProbe.reset()
        _ = failing.body
        let again = TapProbe.drain()
        for action in again.dropFirst() { action() }
        try await settleHosted(failingHost, milliseconds: 250)
        _ = failing.body
        dismissPresentedSheets()
    }

    func testTheSystemFileExportAndPresentWithAHost() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("gap-code-export.html")
        try Data("<html></html>".utf8).write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let window = hostWindow(Text("Host"))
        addTeardownBlock { window?.isHidden = true }
        Presenter.hostOverride = window?.rootViewController
        defer { Presenter.hostOverride = nil }
        try SystemCodeFileExporter().export(url: file)
        try SystemCodeFilePresenter().present(url: file)
        XCTAssertNoThrow(try SystemCodeFileExporter().export(url: file))
        dismissPresentedSheets()
    }

    func testTheSystemFileExportAndPresent() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("gap-code.html")
        try Data("<html></html>".utf8).write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let window = hostWindow(Text("Host"))
        addTeardownBlock { window?.isHidden = true }
        guard Presenter.topViewController != nil else { return }
        try SystemCodeFileExporter().export(url: file)
        try SystemCodeFilePresenter().present(url: file)
        XCTAssertNoThrow(try SystemCodeFileExporter().export(url: file))
    }
}

@MainActor
extension CodeBlockGapTests {
    func testSmokeTheNoticeAndPreviewOutcomes() async throws {
        let (actions, presenter, exporter) = makeActions()
        presenter.failure = PresenterError.noHost
        exporter.failure = PresenterError.noHost
        let noticeView = CodeBlockView(block: block, question: "Was ist das?", actions: actions)
        let noticeHost = mountView(noticeView, size: CGSize(width: 390, height: 420))
        try await settleHosted(noticeHost, milliseconds: 250)
        for action in MirrorTap.actions(in: noticeView.body) { action() }
        try await settleHosted(noticeHost, milliseconds: 300)
        _ = noticeView.body
        let (previewActions, _, _) = makeActions()
        let previewView = CodeBlockView(block: block, question: nil, actions: previewActions)
        let previewHost = mountView(previewView, size: CGSize(width: 390, height: 420))
        try await settleHosted(previewHost, milliseconds: 250)
        for action in MirrorTap.actions(in: previewView.body) { action() }
        try await settleHosted(previewHost, milliseconds: 300)
        _ = previewView.body
        dismissPresentedSheets()
    }
}
