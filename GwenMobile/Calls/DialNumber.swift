import GwenMobileKit
import Foundation

struct DialNumber: Equatable, Hashable, Sendable {
    static let minimumDigits = 3
    static let separators: Set<Character> = [" ", "(", ")", "-", ".", "/", "\u{00A0}", "\u{2011}"]

    let digits: String

    init?(_ raw: String) {
        var kept = ""
        for character in raw.trimmed {
            if character.isASCII, character.isNumber {
                kept.append(character)
            } else if character == "+", kept.isEmpty {
                kept.append(character)
            } else if !Self.separators.contains(character) {
                return nil
            }
        }
        guard kept.filter(\.isNumber).count >= Self.minimumDigits else { return nil }
        digits = kept
    }

    var telURL: URL? { URL(string: "tel:" + digits) }

    var masked: String {
        let visible = 2
        guard digits.count > visible else { return digits }
        return String(repeating: "•", count: digits.count - visible) + digits.suffix(visible)
    }
}
