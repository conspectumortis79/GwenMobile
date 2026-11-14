import GwenMobileKit
import Foundation

struct TranscriptAssembly: Equatable, Sendable {
    private(set) var settled = ""
    private(set) var pending = ""

    var text: String {
        guard !pending.isEmpty else { return settled }
        guard !settled.isEmpty else { return pending }
        var combined = settled
        combined.append(" ")
        combined.append(pending)
        return combined
    }

    mutating func settle(_ piece: String) {
        let trimmed = piece.trimmed
        if !trimmed.isEmpty {
            if !settled.isEmpty { settled.append(" ") }
            settled.append(trimmed)
        }
        pending = ""
    }

    mutating func revise(_ piece: String) {
        pending = piece.trimmed
    }

    mutating func settlePending() {
        guard !pending.isEmpty else { return }
        settle(pending)
    }
}
