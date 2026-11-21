import Foundation

enum CitationMarkers {
    static let pattern = "\\[(\\d{1,2}(?:\\s*[,;]\\s*\\d{1,2})*)\\]"
    static let regex = try? NSRegularExpression(pattern: pattern)

    private static let silent = "[ \\t]*\\[[1-9][0-9]?(?:\\s*[,;]\\s*[1-9][0-9]?)*\\]"
    private static let silentRegex = try? NSRegularExpression(pattern: silent)
    private static let numberRegex = try? NSRegularExpression(pattern: "\\d{1,2}")

    static func stripped(from text: String) -> String {
        guard let silentRegex else { return text }
        return silentRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                    withTemplate: "")
    }

    static func pieces(of list: String) -> [(text: String, number: Int?)] {
        guard let numberRegex else { return [(list, nil)] }
        let source = list as NSString
        var pieces: [(String, Int?)] = []
        var cursor = 0
        for match in numberRegex.matches(in: list, range: NSRange(location: 0, length: source.length)) {
            if match.range.location > cursor {
                pieces.append((source.substring(with: NSRange(location: cursor,
                                                              length: match.range.location - cursor)), nil))
            }
            let raw = source.substring(with: match.range)
            pieces.append((raw, Int(raw)))
            cursor = match.range.location + match.range.length
        }
        if cursor < source.length {
            pieces.append((source.substring(from: cursor), nil))
        }
        return pieces
    }

    static func numbers(in list: String) -> [Int] {
        pieces(of: list).compactMap(\.number)
    }

    static func shifted(_ text: String, by offset: Int, sources count: Int) -> String {
        guard offset > 0, count > 0, let regex, let numberRegex else { return text }
        let source = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed()
        for match in matches {
            let inside = source.substring(with: match.range(at: 1)) as NSString
            let shifted = NSMutableString(string: inside as String)
            let numbers = numberRegex.matches(in: inside as String,
                                              range: NSRange(location: 0, length: inside.length)).reversed()
            for number in numbers {
                let raw = inside.substring(with: number.range)
                guard let value = Int(raw), (1...count).contains(value) else { continue }
                shifted.replaceCharacters(in: number.range, with: String(value + offset))
            }
            source.replaceCharacters(in: match.range, with: "[" + (shifted as String) + "]")
        }
        return source as String
    }
}
