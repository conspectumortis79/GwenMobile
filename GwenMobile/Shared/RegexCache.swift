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
}
