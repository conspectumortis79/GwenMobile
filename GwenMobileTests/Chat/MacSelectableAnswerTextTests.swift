#if targetEnvironment(macCatalyst)
import SwiftUI
import XCTest
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import GwenMobileKit

@MainActor
final class MacSelectableAnswerTextTests: XCTestCase {
    func testTheNativeViewSelectsAndCarriesTheBubbleInsets() {
        let view = MacSelectableAnswerText(attributed: AttributedString("Hallo Welt"),
                                           textColor: .label, onOpen: { _ in false })
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        if let window = Presenter.windowRootViewController?.view.window {
            window.addSubview(controller.view)
        }
        controller.view.layoutIfNeeded()
        addTeardownBlock { controller.view.removeFromSuperview() }
        let textView = Self.findTextView(controller.view)
        XCTAssertNotNil(textView)
        XCTAssertFalse(textView?.isEditable ?? true)
        XCTAssertTrue(textView?.isSelectable ?? false)
        XCTAssertFalse(textView?.isScrollEnabled ?? true)
        XCTAssertEqual(textView?.textContainerInset.top, 9)
        XCTAssertEqual(textView?.textContainerInset.left, 14)
        XCTAssertGreaterThan(textView?.frame.height ?? 0, 18,
                             "die Bubble-Höhe muss den Innenabstand enthalten")
    }

    func testUnstyledTextUsesTheBubbleColor() {
        let attributed = MacSelectableAnswerText.makeAttributed(AttributedString("Hallo"), textColor: .white)
        XCTAssertEqual(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .white)
    }

    func testBoldAndItalicBecomeFontTraits() {
        let attributed = MarkdownRenderer.inline("**fett** und *kursiv* normal")
        let converted = MacSelectableAnswerText.makeAttributed(attributed, textColor: .label)
        let bold = converted.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(bold?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
        let italicStart = converted.string.distance(from: converted.string.startIndex,
                                                   to: converted.string.range(of: "kursiv")?.lowerBound
                                                       ?? converted.string.startIndex)
        let italic = converted.attribute(.font, at: italicStart, effectiveRange: nil) as? UIFont
        XCTAssertTrue(italic?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false)
    }

    func testCitationColorAndLinkSurviveTheConversion() {
        var attributed = AttributedString("Berlin liegt an der Spree [1].")
        guard let range = attributed.range(of: "[1]") else { return XCTFail("Markierung fehlt") }
        attributed[range].link = URL(string: "gwen-source://1")
        attributed[range].foregroundColor = .blue
        let converted = MacSelectableAnswerText.makeAttributed(attributed, textColor: .label)
        let index = converted.string.distance(from: converted.string.startIndex,
                                              to: converted.string.range(of: "[1]")?.lowerBound
                                                  ?? converted.string.startIndex)
        XCTAssertEqual(converted.attribute(.foregroundColor, at: index, effectiveRange: nil) as? UIColor,
                       .systemBlue)
        XCTAssertNotNil(converted.attribute(.link, at: index, effectiveRange: nil))
    }

    func testClaimHighlightKeepsBackgroundAndMarkerLink() {
        var attributed = AttributedString("Aussage")
        attributed.backgroundColor = .orange.opacity(0.16)
        var marker = AttributedString(" \u{26A0}\u{FE0E}")
        marker.link = URL(string: "gwen-claim://0")
        marker.foregroundColor = .orange
        attributed.append(marker)
        let converted = MacSelectableAnswerText.makeAttributed(attributed, textColor: .label)
        XCTAssertNotNil(converted.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        let markerIndex = converted.string.distance(from: converted.string.startIndex,
                                                    to: converted.string.range(of: "\u{26A0}\u{FE0E}")?.lowerBound
                                                        ?? converted.string.startIndex)
        XCTAssertNotNil(converted.attribute(.link, at: markerIndex, effectiveRange: nil))
    }

    func testLineSpacingMatchesTheSwiftUIBubble() {
        let converted = MacSelectableAnswerText.makeAttributed(AttributedString("Zeile eins\nZeile zwei"),
                                                               textColor: .label)
        let style = converted.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.lineSpacing, 3)
    }

    private static func findTextView(_ view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        for child in view.subviews {
            if let found = findTextView(child) { return found }
        }
        return nil
    }
}
#endif
