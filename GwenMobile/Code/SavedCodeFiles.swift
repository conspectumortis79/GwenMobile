import GwenMobileKit
import Foundation

@MainActor
final class SavedCodeFiles {
    static let capacity = 8

    private let exporter: CodeFileExporter
    private let fileManager: FileManager
    private var written: [(key: String, url: URL)] = []

    init(exporter: CodeFileExporter = CodeFileExporter(), fileManager: FileManager = .default) {
        self.exporter = exporter
        self.fileManager = fileManager
    }

    static let shared = SavedCodeFiles()

    func url(for block: CodeBlock, question: String?, date: Date = Date()) throws -> URL {
        let key = "\(block.language.rawValue)\u{1}\(block.code)"
        if let known = written.first(where: { $0.key == key }), fileManager.fileExists(atPath: known.url.path) {
            return known.url
        }
        let url = try exporter.write(block, question: question, date: date)
        written.removeAll { $0.key == key }
        written.append((key, url))
        while written.count > Self.capacity { written.removeFirst() }
        return url
    }
}
