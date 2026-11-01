import Foundation

enum SpeechSentences {
    static let minimumLength = 24

    static func take(from buffer: inout String) -> [String] {
        var sentences: [String] = []
        while let cut = firstCut(in: buffer) {
            sentences.append(String(buffer[..<cut]))
            buffer = String(buffer[cut...])
        }
        return sentences
    }

    private static func firstCut(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\n" {
                guard next < text.endIndex, text[next] == "\n" else {
                    index = next
                    continue
                }
                let after = text.index(after: next)
                let segment = text[..<after]
                if ready(segment) { return after }
                index = after
                continue
            }
            if character == "." || character == "!" || character == "?" || character == "…" {
                guard next < text.endIndex else { return nil }
                let follower = text[next]
                guard follower.isWhitespace || follower == "\"" || follower == "\u{201D}" || follower == ")" else {
                    index = next
                    continue
                }
                let segment = text[..<next]
                if ready(segment), !endsInAbbreviation(segment) { return next }
            }
            index = next
        }
        return nil
    }

    private static func ready(_ segment: Substring) -> Bool {
        let count = String(segment).trimmingCharacters(in: .whitespacesAndNewlines).count
        return count >= minimumLength && !hasOpenFence(segment)
    }

    private static func hasOpenFence(_ segment: Substring) -> Bool {
        String(segment).components(separatedBy: "```").count % 2 == 0
    }

    private static func endsInAbbreviation(_ segment: Substring) -> Bool {
        guard segment.last == "." else { return false }
        let text = String(segment).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dot = text.lastIndex(of: "."), dot > text.startIndex else { return false }
        if text[text.index(before: dot)].isNumber { return true }
        var start = dot
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard text[previous].isLetter else { break }
            start = previous
        }
        return text[start..<dot].count <= 2
    }
}
