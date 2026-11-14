import GwenMobileKit
import Foundation

struct PhraseMatch: Sendable {
    var phrases: [String]

    func matches(_ lowered: String) -> Bool {
        phrases.contains { lowered.contains($0) }
    }
}

enum IntentHeuristics {
    static let safetyRejection = PhraseMatch(phrases: ["datainspectionfailed", "green net", "content_filter"])
    static let contentPolicyRejection = PhraseMatch(phrases: ["content policy", "inappropriate", "safety"])
    static let invalidInput = PhraseMatch(phrases: ["invalidparameter", "invalid_parameter", "invalid input"])
    static let timeoutInterruption = PhraseMatch(phrases: ["timed out", "timeout", "deadline exceeded"])
}
