@testable import GwenMobileFeatureCore
import GwenMobileKit
import Foundation
import SwiftUI

@MainActor
enum StreamingRenderCache {
    private static var partsText = ""
    private static var parts: [AnswerSegment] = []
    private static var markdownText = ""
    private static var markdown = AttributedString()

    static func answerParts(_ text: String) -> [AnswerSegment] {
        guard text.contains(CodeText.fence) else { return [.prose(text)] }
        if text == partsText { return parts }
        let segments = CodeText.segments(from: text)
        let result = segments.contains { $0.code != nil } ? segments : [.prose(text)]
        partsText = text
        parts = result
        return result
    }

    static func inlineMarkdown(_ text: String) -> AttributedString {
        if text == markdownText { return markdown }
        let made = MarkdownRenderer.inline(text)
        markdownText = text
        markdown = made
        return made
    }
}
