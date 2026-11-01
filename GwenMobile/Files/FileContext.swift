import GwenMobileKit
import Foundation

struct FileContext: Equatable, Sendable {
    let text: String
    let kept: [AttachedFile]

    var isEmpty: Bool { text.isEmpty }
    var keptNames: [String] { kept.map(\.name) }

    static func build(for files: [AttachedFile], text: (AttachedFile) -> String?) -> FileContext {
        var blocks: [(file: AttachedFile, block: String, chars: Int)] = []
        for file in files where file.hasText {
            guard let body = text(file), !body.isEmpty else { continue }
            blocks.append((file, FileTextBlocks.file(name: file.name, pages: file.pages, text: body,
                                                     via: file.via, truncated: file.truncated), body.count))
        }
        guard !blocks.isEmpty else { return FileContext(text: "", kept: []) }
        let joined = FileTextBlocks.joinedWithinBudget(blocks, budget: FilePolicy.maxContextChars,
                                                      size: \.chars, block: \.block)
        guard !joined.text.isEmpty else {
            return FileContext(text: FileTextBlocks.omittedNotice(blocks.count), kept: [])
        }
        var digest = joined.text
        if joined.dropped > 0 { digest += "\n\n" + FileTextBlocks.omittedNotice(joined.dropped) }
        return FileContext(text: digest, kept: joined.kept.map(\.file))
    }
}
