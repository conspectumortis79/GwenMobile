import GwenMobileKit
import Foundation

struct CodeBlock: Equatable, Sendable {
    var language: CodeLanguage
    var lines: [String]

    var code: String { lines.joined(separator: "\n") }
    var lineCount: Int { lines.count }
    var isEmpty: Bool { lines.isEmpty }
}

enum AnswerSegment: Equatable, Sendable {
    case prose(String)
    case code(CodeBlock)

    var code: CodeBlock? {
        if case .code(let block) = self { return block }
        return nil
    }

    var prose: String? {
        if case .prose(let text) = self { return text }
        return nil
    }
}

enum CodeText {
    static let fence = "```"

    struct FenceOpening: Equatable, Sendable {
        let length: Int
        let label: String
    }

    static func segments(from text: String) -> [AnswerSegment] {
        var segments: [AnswerSegment] = []
        var prose: [String] = []
        var code: [String] = []
        var fenceLabel: String?
        var fenceOpening: FenceOpening?

        func closeProse() {
            let body = prose.joined(separator: "\n").trimmed
            prose = []
            if !body.isEmpty { segments.append(.prose(body)) }
        }

        func closeCode() {
            let block = CodeBlock(language: CodeLanguage.resolved(fenceLabel: fenceLabel,
                                                                  code: code.joined(separator: "\n")),
                                  lines: trimBlankEdges(code))
            code = []
            fenceLabel = nil
            fenceOpening = nil
            if !block.isEmpty { segments.append(.code(block)) }
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let opening = fenceOpening {
                if closesFence(trimmed, opening: opening) {
                    closeCode()
                } else {
                    code.append(line)
                }
                continue
            }
            if let opening = openingFence(trimmed) {
                closeProse()
                fenceOpening = opening
                fenceLabel = opening.label
                continue
            }
            prose.append(line)
        }
        if fenceOpening != nil { closeCode() } else { closeProse() }
        return segments
    }

    #if DEBUG
    static func blocks(in text: String) -> [CodeBlock] {
        segments(from: text).compactMap(\.code)
    }
    #endif

    static func openingFence(_ trimmedLine: String) -> FenceOpening? {
        let ticks = trimmedLine.prefix { $0 == "`" }
        guard ticks.count >= fence.count else { return nil }
        let label = trimmedLine.dropFirst(ticks.count).trimmingCharacters(in: .whitespaces)
        guard !label.contains("`") else { return nil }
        return FenceOpening(length: ticks.count, label: label)
    }

    static func closesFence(_ trimmedLine: String, opening: FenceOpening) -> Bool {
        let ticks = trimmedLine.prefix { $0 == "`" }
        guard ticks.count >= opening.length else { return false }
        return trimmedLine.dropFirst(ticks.count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func trimBlankEdges(_ lines: [String]) -> [String] {
        var kept = lines
        while kept.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { kept.removeFirst() }
        while kept.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { kept.removeLast() }
        return kept
    }
}
