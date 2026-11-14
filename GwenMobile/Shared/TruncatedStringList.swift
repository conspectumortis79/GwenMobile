import Foundation

public enum TruncatedStringList {
    private static let literal = try? NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)

    public static func strings(under key: String, in text: String) -> [String] {
        guard let literal, let named = text.range(of: "\"\(key)\""),
              let open = text[named.upperBound...].firstIndex(of: "[") else { return [] }
        let body = String(text[text.index(after: open)...]) as NSString
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
