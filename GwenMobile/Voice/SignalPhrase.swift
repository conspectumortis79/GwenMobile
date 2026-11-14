import GwenMobileKit
import Foundation

struct SpokenWord: Equatable, Sendable {
    let folded: String
    let range: Range<String.Index>
}

struct SignalPhrase: Equatable, Sendable {
    static let tolerantLength = 4

    let words: [String]

    init(_ text: String) {
        words = Self.words(in: text).map(\.folded)
    }

    var isEmpty: Bool { words.isEmpty }

    static let alternativeMarks = CharacterSet(charactersIn: ",;")

    static func alternatives(_ text: String) -> [SignalPhrase] {
        text.components(separatedBy: alternativeMarks).map(SignalPhrase.init).filter { !$0.isEmpty }
    }

    static func words(in text: String) -> [SpokenWord] {
        var found: [SpokenWord] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let isWordCharacter = text[index].isLetter || text[index].isNumber
            if isWordCharacter, start == nil { start = index }
            if !isWordCharacter, let begin = start {
                found.append(SpokenWord(folded: fold(text[begin..<index]), range: begin..<index))
                start = nil
            }
            index = text.index(after: index)
        }
        if let begin = start { found.append(SpokenWord(folded: fold(text[begin...]), range: begin..<text.endIndex)) }
        return found
    }

    func trailingMatch(in spoken: [SpokenWord]) -> Int? {
        guard !isEmpty, spoken.count >= words.count else { return nil }
        let start = spoken.count - words.count
        return matches(spoken, at: start) ? start : nil
    }

    func matchesWhole(_ spoken: [SpokenWord]) -> Bool {
        !isEmpty && spoken.count == words.count && matches(spoken, at: 0)
    }

    func lastMatch(in spoken: [SpokenWord]) -> Range<Int>? {
        guard !isEmpty, spoken.count >= words.count else { return nil }
        for start in stride(from: spoken.count - words.count, through: 0, by: -1) where matches(spoken, at: start) {
            return start..<start + words.count
        }
        return nil
    }

    private func matches(_ spoken: [SpokenWord], at start: Int) -> Bool {
        words.indices.allSatisfy { Self.similar(words[$0], spoken[start + $0].folded) }
    }

    static func similar(_ wanted: String, _ heard: String) -> Bool {
        guard wanted != heard else { return true }
        guard wanted.count >= tolerantLength, heard.count >= tolerantLength else { return false }
        return distance(Array(wanted), Array(heard)) <= 1
    }

    private static func fold<S: StringProtocol>(_ text: S) -> String {
        TextFolding.fold(String(text))
    }

    private static func distance(_ left: [Character], _ right: [Character]) -> Int {
        var previous = Array(0...right.count)
        for (row, letter) in left.enumerated() {
            var current = [row + 1]
            for (column, other) in right.enumerated() {
                current.append(min(previous[column + 1] + 1, current[column] + 1,
                                   previous[column] + (letter == other ? 0 : 1)))
            }
            previous = current
        }
        return previous[right.count]
    }
}
