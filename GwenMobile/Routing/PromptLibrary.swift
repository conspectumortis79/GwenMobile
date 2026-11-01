import GwenMobileKit
import Foundation

enum PromptLibrary {
    static func text(_ key: String, _ values: [String: String] = [:]) -> String {
        render(template(key), values)
    }

    static func render(_ template: String, _ values: [String: String]) -> String {
        var text = template
        for (name, value) in values {
            text = text.replacingOccurrences(of: "{{\(name)}}", with: value)
        }
        return text
    }

    private static let defaultStringReader: @Sendable (URL) throws -> String = { url in
        try String(contentsOf: url, encoding: .utf8)
    }

    #if DEBUG
    nonisolated(unsafe) static var stringReader: @Sendable (URL) throws -> String = defaultStringReader {
        didSet {
            cache.removeAll()
            fieldCache.removeAll()
        }
    }
    #else
    static let stringReader: @Sendable (URL) throws -> String = defaultStringReader
    #endif

    static func template(_ key: String) -> String {
        if let cached = cache.value(for: key) { return cached }
        guard let url = Bundle.main.url(forResource: key, withExtension: "md") else {
            flowLog.error("PROMPT datei fehlt key=\(key, privacy: .public)")
            return ""
        }
        let raw: String
        do {
            raw = try stringReader(url)
        } catch {
            flowLog.error("PROMPT lesen fehlgeschlagen key=\(key, privacy: .public) \(error.localizedDescription, privacy: .public)")
            return ""
        }
        let trimmed = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        cache.setValue(trimmed, for: key)
        return trimmed
    }

    static func field(_ key: String, _ name: String, _ values: [String: String] = [:]) -> String {
        render(fields(key)[name] ?? "", values)
    }

    static func fields(_ key: String) -> [String: String] {
        if let cached = fieldCache.value(for: key) { return cached }
        var values: [String: String] = [:]
        for line in template(key).components(separatedBy: "\n") {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            values[name] = value
        }
        fieldCache.setValue(values, for: key)
        return values
    }

    private static let cache = LockedDictionary<String, String>(capacity: 128)
    private static let fieldCache = LockedDictionary<String, [String: String]>(capacity: 64)
}
