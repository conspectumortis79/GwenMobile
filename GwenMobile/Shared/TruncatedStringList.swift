import Foundation

public enum TruncatedStringList {
    private static let literal = try? NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)
    private static let arrayHeads = RegexCache()

    public static func strings(under key: String, in text: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let literal,
              let head = arrayHeads.regex("\"\(escaped)\"\\s*:\\s*\\["),
              let match = head.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return [] }
        let body = String(text[range.upperBound...]) as NSString
        var found: [String] = []
        var cursor = 0
        for match in literal.matches(in: body as String, range: NSRange(location: 0, length: body.length)) {
            let gap = body.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            guard gap.allSatisfy({ $0.isWhitespace || $0 == "," }) else { break }
            let raw = Data(body.substring(with: match.range).utf8)
            guard let value = try? JSONSerialization.jsonObject(with: raw, options: .fragmentsAllowed) as? String
            else { break }
            found.append(value)
            cursor = match.range.location + match.range.length
        }
        return found
    }
}
