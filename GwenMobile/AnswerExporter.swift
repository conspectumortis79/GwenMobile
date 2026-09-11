import Foundation

struct AnswerExporter {
    static let maxTitleWords = 9
    static let fallbackPrefix = "antwort"
    private static let fileNamePattern = "yyyy-MM-dd-HHmmss"

    private let paths: StoragePaths
    private let fileManager: FileManager

    init(paths: StoragePaths = StoragePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    static func title(from question: String?) -> String {
        let words = (question ?? "")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { word in String(word.filter { $0.isLetter || $0.isNumber }) }
            .filter { !$0.isEmpty }
        return words.prefix(maxTitleWords).joined(separator: " ")
    }

    static func fileName(question: String?, date: Date) -> String {
        let title = title(from: question)
        guard !title.isEmpty else { return timestampedName(date: date) }
        return "\(title).html"
    }

    static func timestampedName(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = fileNamePattern
        return "\(fallbackPrefix)-\(formatter.string(from: date)).html"
    }

    func write(text: String, sources: [WebSource], question: String?, model: String? = nil,
               elapsed: Double? = nil, time: String? = nil, date: Date = Date()) throws -> URL {
        try fileManager.createDirectory(at: paths.answers, withIntermediateDirectories: true)
        let document = AnswerHTML.document(
            text: text,
            sources: sources,
            heading: L.t("web_sources_head"),
            title: question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            meta: AnswerHTML.metaLine(model: model, elapsed: elapsed, time: time),
            language: L.lang.rawValue
        )
        let url = paths.answers.appendingPathComponent(
            uniqueName(Self.fileName(question: question, date: date))
        )
        try document.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func uniqueName(_ wanted: String) -> String {
        guard fileManager.fileExists(atPath: paths.answers.appendingPathComponent(wanted).path) else {
            return wanted
        }
        let base = (wanted as NSString).deletingPathExtension
        for suffix in 2...999 {
            let candidate = "\(base) \(suffix).html"
            if !fileManager.fileExists(atPath: paths.answers.appendingPathComponent(candidate).path) {
                return candidate
            }
        }
        return Self.timestampedName(date: Date())
    }
}
