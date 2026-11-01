import Foundation

public extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public extension StringProtocol {
    var trimmed: String { String(self).trimmingCharacters(in: .whitespacesAndNewlines) }
}

public extension Collection {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}

public enum TextLine {
    public static func oneLine(_ text: String, limit: Int) -> String {
        String(text.replacingOccurrences(of: "\n", with: " ").prefix(limit))
    }
}

public enum HTMLText {
    public static let invisibleBlocks = ["script", "style"]
    public static let pageNoiseBlocks = invisibleBlocks + ["noscript", "svg", "header", "footer", "nav"]

    private static let tag = regex("<[^>]+>")
    private static let spaces = regex("\\s{2,}")
    private static let blockCache = RegexCache(options: [.caseInsensitive])

    public static func plain(_ markup: String, hiding blocks: [String]) -> String {
        var text = markup
        if let block = blockRegex(for: blocks) {
            text = replace(block, in: text)
        }
        if let tag {
            text = replace(tag, in: text)
        }
        text = HTMLEntities.decoded(text)
        if let spaces {
            text = replace(spaces, in: text)
        }
        return text.trimmed
    }

    private static func blockRegex(for blocks: [String]) -> NSRegularExpression? {
        guard !blocks.isEmpty else { return nil }
        return blockCache.regex("<(\(blocks.joined(separator: "|")))[\\s\\S]*?</\\1>")
    }

    private static func replace(_ regex: NSRegularExpression, in text: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                       withTemplate: " ")
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }
}
