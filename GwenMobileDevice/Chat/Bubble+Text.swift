@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import UIKit

extension Bubble {
    @ViewBuilder var answerBody: some View {
        let parts = answerParts
        if parts.count == 1, let only = parts.first?.prose {
            proseBubble(only)
        } else {
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    if let block = part.code {
                        CodeBlockView(block: block, question: question, streaming: streaming)
                    } else if let body = part.prose {
                        proseBubble(body)
                    }
                }
            }
        }
    }

    var answerParts: [AnswerSegment] {
        isUser ? [.prose(text)] : StreamingRenderCache.answerParts(text)
    }

    @ViewBuilder func proseBubble(_ body: String) -> some View {
        #if targetEnvironment(macCatalyst)
        if streaming {
            swiftUIBubble(body)
        } else {
            nativeBubble(body)
        }
        #else
        swiftUIBubble(body)
        #endif
    }

    func swiftUIBubble(_ body: String) -> some View {
        rendered(body)
            .scaledFont(17)
            .lineSpacing(3)
            .textSelection(.enabled)
            .suppressingTextFocusRing()
            .environment(\.openURL, answerOpener)
            .foregroundStyle(isUser ? Color.white : Color.primary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(bubbleColor)
            .clipShape(BubbleShape(isUser: isUser))
    }

    #if targetEnvironment(macCatalyst)
    func nativeBubble(_ body: String) -> some View {
        MacSelectableAnswerText(attributed: answerAttributedString(for: body),
                                textColor: isUser ? .white : .label,
                                onOpen: handleAnswerURL)
            .background(bubbleColor)
            .clipShape(BubbleShape(isUser: isUser))
    }
    #endif

    func signatureLine(model: String) -> String {
        var parts = [model]
        if let elapsed { parts.append(String(format: "%.1f s", elapsed)) }
        if let thinking { parts.append(thinking.label) }
        return parts.joined(separator: " · ")
    }

    func sectionHeader(_ title: String) -> some View {
        SectionHeadLine(text: title)
    }

    func rendered(_ body: String) -> Text {
        if streaming { return Text(StreamingRenderCache.inlineMarkdown(body)) }
        return markdownText(for: body)
    }

    func markdownText(for body: String) -> Text {
        Text(answerAttributedString(for: body))
    }

    func answerAttributedString(for body: String) -> AttributedString {
        let review = isUser ? nil : sourceReview
        let key = "\(isUser ? "u" : "a")\u{1}s\(sources.count)\u{1}r\(reviewKey(review))\u{1}\(body)" as NSString
        if let hit = Self.mdCache.object(forKey: key) { return hit.value }
        var attr = MarkdownRenderer.inline(body, phoneLinks: !isUser)
        if !isUser && !sources.isEmpty, let regex = Self.footnoteRegex {
            let plain: String = String(attr.characters)
            let ns = plain as NSString
            let marks = regex.matches(in: plain, range: NSRange(location: 0, length: ns.length))
            for m in marks.reversed() {
                guard let r = Range(m.range, in: attr),
                      let n = Int(ns.substring(with: m.range(at: 1))),
                      n >= 1, n <= sources.count else { continue }
                attr[r].link = URL(string: "gwen-source://\(n)")
                attr[r].foregroundColor = Color.blue
            }
        }
        if let review {
            attr = markedAnswer(attr, review: review)
        }
        Self.mdCache.setObject(AttrBox(attr), forKey: key, cost: body.utf8.count * 4)
        return attr
    }

    func reviewKey(_ review: SourceReview?) -> String {
        guard let review else { return "" }
        return review.results.map { "\($0.verdict.rawValue):\($0.claim)" }.joined(separator: "\u{2}")
    }

    func markedAnswer(_ attr: AttributedString, review: SourceReview) -> AttributedString {
        let marks = review.marks(in: String(attr.characters))
        guard !marks.isEmpty else { return attr }
        var out = AttributedString()
        var cursor = attr.startIndex
        for mark in marks {
            guard let range = Range(mark.range, in: attr) else { continue }
            out.append(attr[cursor..<range.lowerBound])
            var statement = AttributedString(attr[range])
            statement.backgroundColor = claimColour(mark.verdict).opacity(0.16)
            out.append(statement)
            out.append(claimMarker(mark))
            cursor = range.upperBound
        }
        out.append(attr[cursor...])
        return out
    }

    func claimMarker(_ mark: SourceReview.ClaimMark) -> AttributedString {
        let symbol = mark.verdict == .contradicted ? "\u{2716}\u{FE0E}" : "\u{26A0}\u{FE0E}"
        var marker = AttributedString("\u{00A0}\(symbol)")
        marker.link = URL(string: "gwen-claim://\(mark.resultIndex)")
        marker.foregroundColor = claimColour(mark.verdict)
        return marker
    }

    func claimColour(_ verdict: ClaimVerdict) -> Color {
        verdict == .contradicted ? .red : .orange
    }

    static let footnoteRegex = CitationMarkers.regex

    @discardableResult
    func handleAnswerURL(_ url: URL) -> Bool {
        if let number = Self.telNumber(of: url), let onCall {
            onCall(number)
            return true
        }
        if url.scheme == "gwen-claim", let index = Int(url.host ?? ""),
           let results = sourceReview?.results, results.indices.contains(index) {
            claimNote = results[index]
            return true
        }
        guard url.scheme == "gwen-source",
              let n = Int(url.host ?? ""), n >= 1, n <= sources.count else {
            return false
        }
        openSource(sources[n - 1])
        return true
    }

    var answerOpener: OpenURLAction {
        OpenURLAction { url in handleAnswerURL(url) ? .handled : .systemAction }
    }

    nonisolated static func telNumber(of url: URL) -> DialNumber? {
        guard url.scheme?.lowercased() == "tel",
              let colon = url.absoluteString.firstIndex(of: ":") else { return nil }
        let raw = String(url.absoluteString[url.absoluteString.index(after: colon)...])
        return DialNumber(raw.removingPercentEncoding ?? raw)
    }

    var bubbleColor: Color {
        isUser ? Color.blue : Color(.systemGray5)
    }
}
