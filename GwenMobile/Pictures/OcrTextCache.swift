import GwenMobileKit
import Foundation

@MainActor
final class OcrTextCache {
    static let shared = OcrTextCache()
    static let maximumEntries = 24

    private struct Entry {
        let file: String
        let text: String
    }

    private var entries: [Entry] = []

    init() {}

    func remember(_ text: String, for file: String) {
        entries.removeAll { $0.file == file }
        entries.append(Entry(file: file, text: text))
        while entries.count > Self.maximumEntries { entries.removeFirst() }
    }

    func text(for file: String) -> String? {
        entries.first { $0.file == file }?.text
    }
}
