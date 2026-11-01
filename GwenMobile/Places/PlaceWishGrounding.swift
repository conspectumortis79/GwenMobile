import GwenMobileKit
import Foundation

enum PlaceWishGrounding {
    static let abbreviationLengths = 3...4
    static let groundedShare = 0.6

    static func overlap(of label: String, with wish: String) -> Int {
        let labelWords = words(in: label)
        return Set(words(in: wish)).filter { heard in labelWords.contains { matches($0, heard) } }.count
    }

    static func isGrounded(_ term: String, in wish: String) -> Bool {
        let heard = words(in: wish)
        let own = words(in: term)
        guard let first = own.first else { return false }
        let present = own.filter { word in heard.contains { matches(word, $0) } }
        let numbersKept = own.filter { $0.allSatisfy(\.isNumber) }.allSatisfy(heard.contains)
        return present.first == first && numbersKept && Double(present.count) / Double(own.count) >= groundedShare
    }

    static func words(in text: String) -> [String] {
        SignalPhrase.words(in: text.uppercased()).map(\.folded)
    }

    private static func matches(_ word: String, _ heard: String) -> Bool {
        if word == heard || SignalPhrase.similar(word, heard) { return true }
        let (short, long) = word.count <= heard.count ? (word, heard) : (heard, word)
        guard abbreviationLengths.contains(short.count), !short.allSatisfy(\.isNumber) else { return false }
        return long.hasPrefix(short)
    }
}

enum PlaceWishConfirmation {
    static let hint = PromptLibrary.text("check_place_terms")

    static let attempts = 2

    static func checkedNearby(_ decision: ToolDecision, wish: String,
                              asking ask: (String) async -> ToolDecision?) async -> ToolDecision {
        var current = decision
        for attempt in 1...attempts where lacksOwnWords(current, wish: wish) {
            flowMarkPersonal("ORT nachfrage versuch=\(attempt) begriffe=\(current.stepDetail)")
            guard var answer = await ask(hint), case .nearbyPlace = answer.route else { break }
            answer.wish = decision.wish
            flowMarkPersonal("ORT nachfrage antwort=\(answer.stepDetail)")
            current = answer
        }
        return current
    }

    private static func lacksOwnWords(_ decision: ToolDecision, wish: String) -> Bool {
        guard case .nearbyPlace(let terms, _) = decision.route else { return false }
        return !terms.contains { PlaceWishGrounding.isGrounded($0, in: wish) }
    }
}
