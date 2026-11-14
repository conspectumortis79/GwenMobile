import GwenMobileKit
import Foundation

struct ArtifactNaming {
    static let maxTitleWords = 9
    static let maxTitleChars = 80

    let directory: URL
    let fileExtension: String
    let fallbackPrefix: String
    let fileManager: FileManager

    init(directory: URL, fileExtension: String, fallbackPrefix: String,
         fileManager: FileManager = .default) {
        self.directory = directory
        self.fileExtension = fileExtension
        self.fallbackPrefix = fallbackPrefix
        self.fileManager = fileManager
    }

    static func title(from question: String?) -> String {
        let words = (question ?? "")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { word in String(word.filter { $0.isLetter || $0.isNumber }) }
            .filter { !$0.isEmpty }
            .prefix(maxTitleWords)
            .joined(separator: " ")
        return String(words.prefix(maxTitleChars)).trimmed
    }

    static func stamped(prefix: String, date: Date, fileExtension: String) -> String {
        "\(prefix)-\(Formatters.fileStamp(date)).\(fileExtension)"
    }

    func name(from question: String?, date: Date = Date()) -> String {
        let title = Self.title(from: question)
        guard !title.isEmpty else {
            return Self.stamped(prefix: fallbackPrefix, date: date, fileExtension: fileExtension)
        }
        return "\(title).\(fileExtension)"
    }

    func uniqueName(from question: String?, date: Date = Date()) -> String {
        let wanted = name(from: question, date: date)
        let base = (wanted as NSString).deletingPathExtension
        return FreeName.first({ $0.map { "\(base) \($0).\(fileExtension)" } ?? wanted }, upTo: 999, isTaken: taken)
            ?? Self.stamped(prefix: fallbackPrefix, date: date, fileExtension: fileExtension)
    }

    func url(named name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    func prepare(question: String?, date: Date = Date()) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return url(named: uniqueName(from: question, date: date))
    }

    private func taken(_ name: String) -> Bool {
        fileManager.fileExists(atPath: url(named: name).path)
    }
}
