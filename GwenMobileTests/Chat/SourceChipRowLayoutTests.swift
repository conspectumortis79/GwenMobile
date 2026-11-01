@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class SourceChipRowLayoutTests: GwenTestCase {
    private let phoneWidth: CGFloat = 393
    private let domains = ["de.wikipedia.org", "gettyimages.de", "gala.de", "cinema.de", "youtube.com",
                           "filmstarts.de", "hellomagazine.com", "vogue.de", "spiegel.de", "imdb.com",
                           "rollingstone.de"]

    private func answer(sources count: Int) -> ChatMessage {
        let sources = domains.prefix(count).map { WebSource(title: $0, url: "https://\($0)/", domain: $0) }
        return ChatMessage(role: .assistant, text: "Natalie Portman ist Schauspielerin [1].", model: "probe",
                           sources: Array(sources))
    }

    private func bubble(_ message: ChatMessage) -> Bubble {
        Bubble(message: message, media: scratchMediaStore(), photos: PhotoLibraryWriter())
    }

    private func fittedWidth(_ message: ChatMessage) -> CGFloat {
        UIHostingController(rootView: bubble(message))
            .sizeThatFits(in: CGSize(width: phoneWidth, height: UIView.layoutFittingExpandedSize.height)).width
    }

    private func present<Content: View>(_ content: Content, height: CGFloat = 400) async throws -> UIView {
        await waitUntil({ UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene } }, timeout: 5)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: phoneWidth, height: height)
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.makeKeyAndVisible()
        addTeardownBlock {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.layoutIfNeeded()
        try await settle()
        return host.view
    }

    private func swipeableRows(in view: UIView) -> [UIScrollView] {
        scrollViews(in: view).filter { $0.contentSize.width > $0.bounds.width + 1 }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        let own = (view as? UIScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { scrollViews(in: $0) }
    }

    func testManySourcesNeverWidenTheAnswerBeyondTheScreen() {
        XCTAssertLessThanOrEqual(fittedWidth(answer(sources: 11)), phoneWidth + 0.5,
                                 "elf Quellen dürfen die Chat-Spalte nicht breiter als das iPhone machen")
    }

    func testFewSourcesFitWithoutChangingTheWidth() {
        XCTAssertLessThanOrEqual(fittedWidth(answer(sources: 2)), phoneWidth + 0.5)
    }

    func testManySourcesBecomeARowThatCanBeSwiped() async throws {
        let root = try await present(bubble(answer(sources: 11)))
        let rows = swipeableRows(in: root)
        XCTAssertEqual(rows.count, 1, "genau die Quellenreihe ist seitlich wischbar")
        XCTAssertLessThanOrEqual(rows.first?.bounds.width ?? .infinity, phoneWidth)
        XCTAssertEqual(rows.first?.contentOffset.x ?? -1, 0, accuracy: 1, "die Reihe beginnt bei Quelle 1")
    }

    func testFewSourcesStayAStillRow() async throws {
        let root = try await present(bubble(answer(sources: 3)))
        XCTAssertTrue(swipeableRows(in: root).isEmpty, "drei kompakte Quellen passen, da gibt es nichts zu wischen")
    }

    func testScrollingTheThreadToTheAnswerLeavesTheChipsAtTheirStart() async throws {
        let target = ThreadScrollTarget()
        let answer = bubble(answer(sources: 11))
        let view = ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    Color.clear.frame(height: 900)
                    answer.id("antwort")
                }
            }
            .onAppear { target.scroll = { proxy.scrollTo($0, anchor: .bottom) } }
        }
        let root = try await present(view, height: 600)
        target.scroll?("antwort")
        try await settle()
        let row = try XCTUnwrap(swipeableRows(in: root).first)
        XCTAssertEqual(row.contentOffset.x, 0, accuracy: 1,
                       "das Nachziehen des Chats ans Ende darf die Quellenreihe nicht mitscrollen")
    }

    func testAnAnswerThatGainsSourcesStartsItsRowAtTheFirstChip() async throws {
        let shown = GrowingAnswer(answer(sources: 4))
        let root = try await present(GrowingAnswerView(shown: shown, media: scratchMediaStore(),
                                                       photos: PhotoLibraryWriter()))
        XCTAssertTrue(swipeableRows(in: root).isEmpty, "vier Quellen passen noch ohne Wischen")
        shown.message = answer(sources: 9)
        let grown = try await present(GrowingAnswerView(shown: shown, media: scratchMediaStore(),
                                                        photos: PhotoLibraryWriter()))
        await waitUntil({ !self.swipeableRows(in: grown).isEmpty }, timeout: 8)
        let row = try XCTUnwrap(swipeableRows(in: grown).first)
        XCTAssertEqual(row.contentOffset.x, 0, accuracy: 1,
                       "kommen weitere Quellen dazu, beginnt die Reihe trotzdem bei Quelle 1")
    }
}

@MainActor
private final class ThreadScrollTarget {
    var scroll: ((String) -> Void)?
}

@MainActor
private final class GrowingAnswer: ObservableObject {
    @Published var message: ChatMessage

    init(_ message: ChatMessage) {
        self.message = message
    }
}

private struct GrowingAnswerView: View {
    @ObservedObject var shown: GrowingAnswer
    let media: MediaStore
    let photos: PhotoLibraryWriter

    var body: some View {
        Bubble(message: shown.message, media: media, photos: photos)
    }
}
