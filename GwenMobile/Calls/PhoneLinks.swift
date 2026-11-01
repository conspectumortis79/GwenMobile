import GwenMobileKit
import Foundation

struct PhoneLink: Equatable {
    let range: Range<String.Index>
    let number: DialNumber
}

enum PhoneLinks {
    static let minimumDigits = 6

    static let pattern = #"(?<![\p{L}\p{N}])(\(?\+?\d[\d \t\x{00A0}()./\x{2011}\-]*\d)(?![\p{L}\p{N}])"#
    static let regex = try? NSRegularExpression(pattern: pattern)

    static let datePattern = #"^\d{1,4}([./])\d{1,2}\1\d{2,4}$"#
    static let dateRegex = try? NSRegularExpression(pattern: datePattern)

    static let trunkPattern = #"\(0+"#
    static let trunkRegex = try? NSRegularExpression(pattern: trunkPattern)

    static func matches(in text: String) -> [PhoneLink] {
        guard let regex else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard var range = Range(match.range, in: text) else { return nil }
            if text[range].hasPrefix("("), !text[range].contains(")") {
                range = text.index(after: range.lowerBound)..<range.upperBound
            }
            guard let number = number(in: String(text[range])) else { return nil }
            return PhoneLink(range: range, number: number)
        }
    }

    private static func number(in candidate: String) -> DialNumber? {
        let cleaned = isInternational(candidate) ? removingTrunkZero(candidate) : candidate
        guard let dialed = DialNumber(cleaned), startsLikeAPhone(candidate),
              !isDate(candidate), dialed.digits.filter(\.isNumber).count >= minimumDigits else { return nil }
        return dialed
    }

    private static func isInternational(_ text: String) -> Bool {
        text.hasPrefix("+") || text.hasPrefix("00")
    }

    private static func removingTrunkZero(_ text: String) -> String {
        guard let trunkRegex else { return text }
        let source = text as NSString
        return trunkRegex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: source.length),
                                                   withTemplate: "(")
    }

    private static func startsLikeAPhone(_ text: String) -> Bool {
        let body = text.hasPrefix("(") ? text.dropFirst() : Substring(text)
        return body.first == "+" || body.first == "0"
    }

    private static func isDate(_ text: String) -> Bool {
        guard let dateRegex else { return false }
        let source = text as NSString
        return dateRegex.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) != nil
    }
}
