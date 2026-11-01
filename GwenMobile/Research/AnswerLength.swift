import GwenMobileKit

struct AnswerLength: Equatable, Sendable {
    static let compactWords = 150
    static let wordsPerItem = 80
    static let detailedFloor = 300
    static let detailedCeiling = 700

    let words: Int
    let items: Int
    let isDetailed: Bool

    static let compact = AnswerLength(words: compactWords, items: 0, isDetailed: false)

    static func detailed(items: Int) -> AnswerLength {
        let counted = max(0, items)
        let words = min(detailedCeiling, max(detailedFloor, counted * wordsPerItem))
        return AnswerLength(words: words, items: counted, isDetailed: true)
    }

    var wordsEach: Int? {
        guard isDetailed, items > 0 else { return nil }
        return words / items
    }

    var traceLine: String {
        "länge=\(words) detail=\(isDetailed) punkte=\(items)"
    }
}
