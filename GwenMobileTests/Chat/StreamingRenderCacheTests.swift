@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class StreamingRenderCacheTests: GwenTestCase {
    func testCodeSegmentsAreCachedAndStayStable() {
        let text = "Vor\n```swift\nlet a = 1\n```\nNach"
        let first = StreamingRenderCache.answerParts(text)
        XCTAssertEqual(first, StreamingRenderCache.answerParts(text), "derselbe Text liefert dasselbe Ergebnis")
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.compactMap(\.code).first?.language, .swift)
        XCTAssertEqual(StreamingRenderCache.answerParts("nur Text"), [.prose("nur Text")])
        XCTAssertEqual(StreamingRenderCache.answerParts("`ohne Zaun`"), [.prose("`ohne Zaun`")])
    }

    func testInlineMarkdownIsCachedPerText() {
        let bold = StreamingRenderCache.inlineMarkdown("**fett**")
        XCTAssertEqual(bold, StreamingRenderCache.inlineMarkdown("**fett**"))
        XCTAssertNotEqual(bold, StreamingRenderCache.inlineMarkdown("normal"))
    }
}
