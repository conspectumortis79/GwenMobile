@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class CodeBlockScrollTests: GwenTestCase {
    private enum CardError: LocalizedError {
        case noWindow, noScroll

        var errorDescription: String? {
            switch self {
            case .noWindow: return "kein Fenster für die Karte"
            case .noScroll: return "kein Scroll-View in der Karte"
            }
        }
    }

    private static var strayWindow: UIWindow?

    private let wide = (0..<40).map { "    Zeile \($0) " + String(repeating: "x", count: 200) }

    private static func presentingRoot() -> UIViewController? {
        if let root = Presenter.windowRootViewController { return root }
        if let window = strayWindow, window.rootViewController != nil { return window.rootViewController }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return nil }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        strayWindow = window
        return window.rootViewController
    }

    private func scroll(in view: UIView) -> UIScrollView? {
        if let found = view as? UIScrollView { return found }
        for child in view.subviews { if let inner = scroll(in: child) { return inner } }
        return nil
    }

    private func present(lines: [String], streaming: Bool) async throws -> (UIHostingController<CodeBlockView>,
                                                                            UIScrollView) {
        let host = UIHostingController(rootView: CodeBlockView(block: CodeBlock(language: .html, lines: lines),
                                                              question: "Tetris?", streaming: streaming))
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 340)
        guard let root = Self.presentingRoot() else { throw CardError.noWindow }
        if root.presentedViewController != nil {
            root.dismiss(animated: false)
            try await settle(300)
        }
        root.present(host, animated: false)
        addTeardownBlock { [weak host] in
            Task { @MainActor in host?.dismiss(animated: false) }
        }
        try await settle(400)
        guard let scroll = scroll(in: host.view) else { throw CardError.noScroll }
        return (host, scroll)
    }

    @MainActor
    private func grow(_ host: UIHostingController<CodeBlockView>, lines: [String], streaming: Bool) {
        host.rootView = CodeBlockView(block: CodeBlock(language: .html, lines: lines), question: "Tetris?",
                                      streaming: streaming)
    }

    @MainActor
    func testStreamingKeepsEveryLineStartOnScreen() async throws {
        let (host, scroll) = try await present(lines: ["<!doctype html>", "<html>"], streaming: true)
        grow(host, lines: wide, streaming: true)
        try await settle(500)
        XCTAssertGreaterThan(scroll.contentSize.width - scroll.bounds.width, 1,
                             "der Probecode muss breiter sein als die Karte, sonst prüft der Test nichts")
        XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 1,
                       "während des Streamens bleibt Spalte 0 sichtbar, die Karte driftet nicht nach rechts")
        XCTAssertGreaterThan(scroll.contentOffset.y, scroll.contentSize.height - scroll.bounds.height - 2,
                             "senkrecht folgt die Karte weiter der neuesten Zeile")
    }

    @MainActor
    func testEveryLateTokenLeavesTheCardAtColumnZero() async throws {
        let (host, scroll) = try await present(lines: Array(wide.prefix(6)), streaming: true)
        for step in 7...wide.count {
            grow(host, lines: Array(wide.prefix(step)), streaming: true)
            try await settle(120)
            XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 1, "Token \(step) schiebt die Karte nach rechts")
        }
    }

    @MainActor
    func testAFinishedAnswerStaysExactlyWhereTheUserLeftIt() async throws {
        let (host, scroll) = try await present(lines: Array(wide.prefix(8)), streaming: false)
        scroll.setContentOffset(CGPoint(x: 420, y: 60), animated: false)
        grow(host, lines: wide, streaming: false)
        try await settle(400)
        XCTAssertEqual(scroll.contentOffset.x, 420, accuracy: 1, "eine fertige Antwort wird nicht umhergeworfen")
        XCTAssertEqual(scroll.contentOffset.y, 60, accuracy: 1)
    }
}
