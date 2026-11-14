import GwenMobileKit
import Foundation

enum PriceEvidence {
    static let minimumMentions = 1

    private static let amount = "(?:\\d[\\d.,\u{00A0}\u{202F} ]*\\d|\\d)"
    private static let symbol = "[€£$¥₽]"
    private static let word = "(?:EUR|USD|GBP|CHF|PLN|CZK|HUF|DKK|NOK|SEK|RUB|JPY|AUD|CAD|RSD|BGN"
        + "|HRK|RON|UAH|TRY|kr|zł|Kč|Ft|lei|Euro|Dollar|руб|грн)"
    private static let letter = "[0-9A-Za-z\u{00C0}-\u{00FF}\u{0400}-\u{04FF}]"
    private static let ahead = "(?!\(letter))"
    private static let behind = "(?<!\(letter))"

    private static let amountFirst = "\(amount)\\s*(?:\(symbol)|\(word)\(ahead))"
    private static let currencyFirst = "(?:\(symbol)|\(behind)\(word)\(ahead))\\s*\(amount)"

    static let pattern = "(?:\(amountFirst)|\(currencyFirst))"

    private static let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

    static func mentions(in text: String) -> Int {
        guard let regex else { return 0 }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).count
    }

    static func hasPrice(_ text: String) -> Bool {
        mentions(in: text) >= minimumMentions
    }

    static func withPrice(_ hits: [WebHit]) -> [WebHit] {
        hits.filter { hasPrice($0.text) }
    }

    static func ranked(_ hits: [WebHit]) -> [WebHit] {
        let priced = hits.filter { hasPrice($0.text) }
        return priced + hits.filter { !hasPrice($0.text) }
    }
}
