import GwenMobileKit
import Foundation

enum AnswerItems {
    static let bulletMarks: [String] = ["- ", "* ", "\u{2022} "]

    static func count(in text: String) -> Int {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(isItem)
            .count
    }

    static func isItem(_ line: String) -> Bool {
        if bulletMarks.contains(where: { line.hasPrefix($0) }) { return true }
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 2 else { return false }
        let rest = line.dropFirst(digits.count)
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }
}
