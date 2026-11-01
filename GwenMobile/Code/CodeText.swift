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

    static func segments(from text: String) -> [AnswerSegment] {
        var segments: [AnswerSegment] = []
        var prose: [String] = []
        var code: [String] = []
        var fenceLabel: String?
        var open = false

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
            if !block.isEmpty { segments.append(.code(block)) }
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !open, isFenceStart(trimmed) {
                closeProse()
                open = true
                fenceLabel = trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
                continue
            }
            if open, trimmed == fence {
                open = false
                closeCode()
                continue
            }
            if open { code.append(line) } else { prose.append(line) }
        }
        if open { closeCode() } else { closeProse() }
        return segments
    }

    #if DEBUG
    static func blocks(in text: String) -> [CodeBlock] {
        segments(from: text).compactMap(\.code)
    }
    #endif

    static func isFenceStart(_ trimmedLine: String) -> Bool {
        guard trimmedLine.hasPrefix(fence) else { return false }
        return !trimmedLine.dropFirst(fence.count).contains(fence)
    }

    private static func trimBlankEdges(_ lines: [String]) -> [String] {
        var kept = lines
        while kept.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { kept.removeFirst() }
        while kept.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { kept.removeLast() }
        return kept
    }
}
