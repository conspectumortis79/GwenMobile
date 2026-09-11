import Foundation

struct AnswerExporter {
    private let paths: StoragePaths
    private let fileManager: FileManager

    init(paths: StoragePaths = StoragePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    private static let fileNamePattern = "yyyy-MM-dd-HHmmss"

    nonisolated static func fileName(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = fileNamePattern
        return "gwen-\(formatter.string(from: date)).md"
    }

    nonisolated static func document(text: String, sources: [WebSource], heading: String) -> String {
        var blocks = [text.trimmingCharacters(in: .whitespacesAndNewlines)]
        if !sources.isEmpty {
            var lines = ["## \(heading)"]
            for (index, source) in sources.enumerated() {
                lines.append("\(index + 1). [\(linkLabel(source))](\(source.url))")
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    private nonisolated static func linkLabel(_ source: WebSource) -> String {
        let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? source.domain : title
    }

    func write(text: String, sources: [WebSource], date: Date = Date()) throws -> URL {
        try fileManager.createDirectory(at: paths.answers, withIntermediateDirectories: true)
        let url = paths.answers.appendingPathComponent(Self.fileName(date: date))
        try Self.document(text: text, sources: sources, heading: L.t("web_sources_head"))
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
