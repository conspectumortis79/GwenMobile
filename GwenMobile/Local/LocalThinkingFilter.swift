import GwenMobileKit
import Foundation

struct LocalThinkingFilter {
    let start: String
    let end: String

    private var active = false
    private var buffer = ""

    init(start: String = "<|channel>thought", end: String = "<channel|>", primed: Bool = false) {
        self.start = start
        self.end = end
        self.active = primed
    }

    mutating func feed(_ text: String) -> String {
        buffer += text
        var output = ""
        while true {
            if active {
                guard let range = buffer.range(of: end) else {
                    let keep = min(buffer.count, end.count - 1)
                    buffer = keep > 0 ? String(buffer.suffix(keep)) : ""
                    break
                }
                buffer = String(buffer[range.upperBound...])
                active = false
                continue
            }
            if let range = buffer.range(of: start) {
                output += buffer[..<range.lowerBound]
                buffer = String(buffer[range.upperBound...])
                active = true
                continue
            }
            let keep = partialPrefixLength()
            if buffer.count > keep {
                let cut = buffer.index(buffer.endIndex, offsetBy: -keep)
                output += buffer[..<cut]
                buffer = String(buffer[cut...])
            }
            break
        }
        return output
    }

    private func partialPrefixLength() -> Int {
        let maximum = min(buffer.count, start.count - 1)
        guard maximum > 0 else { return 0 }
        for length in stride(from: maximum, through: 1, by: -1)
        where start.hasPrefix(String(buffer.suffix(length))) {
            return length
        }
        return 0
    }

    mutating func finish() -> String {
        let rest = active ? "" : buffer
        buffer = ""
        active = false
        return rest
    }
}
