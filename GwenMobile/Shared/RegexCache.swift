import Foundation

public final class RegexCache: @unchecked Sendable {
    private let cache = LockedValue([String: NSRegularExpression]())
    private let options: NSRegularExpression.Options

    public init(options: NSRegularExpression.Options = []) {
        self.options = options
    }

    public func regex(_ pattern: String) -> NSRegularExpression? {
        cache.mutate { stored in
            if let found = stored[pattern] { return found }
            guard let made = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
            stored[pattern] = made
            return made
        }
    }

    public func firstMatch(in text: String, pattern: String) -> String? {
        Self.firstMatch(in: text, regex: regex(pattern))
    }

    public static func firstMatch(in text: String, regex: NSRegularExpression?) -> String? {
        let source = text as NSString
        guard let regex,
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: source.length)),
              match.numberOfRanges > 1,
              match.range(at: 1).location != NSNotFound else { return nil }
        return source.substring(with: match.range(at: 1))
    }
}
