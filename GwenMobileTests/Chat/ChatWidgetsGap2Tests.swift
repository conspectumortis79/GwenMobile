@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class ChatWidgetsGap2Tests: GwenTestCase {
    private func review(verified: Bool = true, contradicted: [String] = [],
                        unsupported: [String] = [], crossChecked: Bool = false, citedClaims: Int = 1,
                        sourceDomains: Int = 1, citedSources: Int = 0,
                        citedOrigins: Int = 0) -> SourceReview {
        var review = SourceReview()
        review.verified = verified
        review.crossChecked = crossChecked
        review.citedClaims = citedClaims
        review.sourceDomains = sourceDomains
        review.citedSources = citedSources
        review.citedOrigins = citedOrigins
        review.contradicted = contradicted
        review.unsupported = unsupported
        review.results = contradicted.map {
            SourceReview.ClaimResult(claim: $0, verdict: .contradicted)
        } + unsupported.map {
            SourceReview.ClaimResult(claim: $0, verdict: .unsupported)
        }
        return review
    }

    func testSmokeTheSourceReviewLinesDrawInEveryState() async throws {
        let states = [review(contradicted: ["a"]), review(contradicted: ["a", "b"]), review(),
                      review(unsupported: ["a"]), review(unsupported: ["a", "b"]),
                      review(crossChecked: true), review(citedClaims: 0, sourceDomains: 2),
                      review(verified: false), review(verified: false, citedClaims: 0),
                      review(verified: false, citedClaims: 2, citedSources: 3, citedOrigins: 1)]
        for state in states {
            let controller = mountView(SourceReviewLine(review: state),
                                       size: CGSize(width: 390, height: 160))
            try await settleHosted(controller, milliseconds: 60)
        }
    }

    func testTheCopyButtonAndMenuItem() async throws {
        var copied = 0
        let copyButton = AnswerCopyButton(text: "Antwort")
        let controller = mountView(copyButton, size: CGSize(width: 200, height: 120))
        try await settleHosted(controller, milliseconds: 100)
        for action in MirrorTap.actions(in: copyButton.body) { action() }
        try await settleHosted(controller, milliseconds: 150)
        _ = copyButton.body
        let item = AnswerCopyMenuItem(text: "Antwort", onCopied: { copied += 1 })
        for action in MirrorTap.actions(in: item.body) { action() }
        XCTAssertEqual(copied, 1)
    }

    func testSmokeTheProcessingDotsDraw() async throws {
        let controller = mountView(ProcessingDots(), size: CGSize(width: 200, height: 60))
        try await settleHosted(controller, milliseconds: 100)
        let tinted = mountView(ProcessingDots(tint: .red), size: CGSize(width: 200, height: 60))
        try await settleHosted(tinted, milliseconds: 100)
    }

    func testTheThreadObservationDefaultsAndDragEnding() {
        _ = ChatThreadObservation()
        let pins = BottomPinTracker(tolerance: ChatAutoScroll.tolerance)
        let scroll = ChatAutoScroll(pins: pins)
        var scrolled: [AnyHashable] = []
        let action: ChatAutoScroll.ScrollAction = { scrolled.append($0) }
        scroll.record(ChatThreadMetrics(contentHeight: 1000, contentWidth: 390, scrollOffset: 0,
                                        viewportHeight: 200, viewportWidth: 390, bottomInset: 0),
                      anchor: "a", using: action)
        scroll.dragChanged(translation: -200)
        scroll.follow("b", using: action)
        scroll.dragEnded("b", using: action)
        XCTAssertFalse(scrolled.isEmpty)
    }

    func testTheReturnToBottomButtonDraws() async throws {
        var taps = 0
        let button = ReturnToBottomButton { taps += 1 }
        let controller = mountView(button, size: CGSize(width: 200, height: 80))
        try await settleHosted(controller, milliseconds: 100)
        for action in MirrorTap.actions(in: button) { action() }
        XCTAssertEqual(taps, 1)
    }

    func testTheChatHeaderDraws() async throws {
        var actions: [String] = []
        let paths = temporaryPaths("chat-header-gap")
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        let header = ChatHeaderView(showHistory: .constant(false),
                                    showSettings: .constant(false),
                                    onNewChat: { actions.append("new") },
                                    onToggleListen: { actions.append("listen") },
                                    onCancelGallery: { actions.append("gallery") })
        let controller = mountView(header.environmentObject(store).environmentObject(GallerySelection()),
                                   size: CGSize(width: 390, height: 120))
        try await settleHosted(controller, milliseconds: 150)
        for action in MirrorTap.actions(in: header) { action() }
        XCTAssertFalse(actions.isEmpty)
    }
}

@MainActor
extension ChatWidgetsGap2Tests {
    func testSmokeTheProcessingDotsWithReduceMotion() async throws {
        ProcessingDots.reduceMotionOverride = { true }
        let calm = mountView(ProcessingDots(), size: CGSize(width: 200, height: 60))
        try await settleHosted(calm, milliseconds: 120)
        ProcessingDots.reduceMotionOverride = { false }
        let moving = mountView(ProcessingDots(), size: CGSize(width: 200, height: 60))
        try await settleHosted(moving, milliseconds: 120)
        ProcessingDots.reduceMotionOverride = { UIAccessibility.isReduceMotionEnabled }
    }
}
