import Foundation

public enum StorageJSON {
    public static func read<Value: Decodable>(_ type: Value.Type, from url: URL,
                                       failures: FailureReporter) -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try decoder.decode(Value.self, from: Data(contentsOf: url))
        } catch {
            let backup = Self.backupURL(for: url)
            let saved = FileManager.default.fileExists(atPath: backup.path)
                || (try? FileManager.default.copyItem(at: url, to: backup)) != nil
            failures.note("lesen fehlgeschlagen: \(error.localizedDescription)"
                          + (saved ? " Sicherung: \(backup.lastPathComponent)" : ""))
            return nil
        }
    }

    private static func backupURL(for url: URL) -> URL {
        url.appendingPathExtension("corrupt")
    }

    @discardableResult public static func write<Value: Encodable>(_ value: Value, to url: URL, support: URL,
                                        failures: FailureReporter) -> Bool {
        do {
            let data = try encoder.encode(value)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            #if os(iOS)
            do {
                try protect(url)
            } catch {
                flowLog.error("SCHUTZ setzen fehlgeschlagen datei=\(url.lastPathComponent, privacy: .public) \(error.localizedDescription, privacy: .public)")
            }
            #endif
            return true
        } catch {
            failures.note("speichern fehlgeschlagen: \(error.localizedDescription)")
            return false
        }
    }

    #if os(iOS)
    nonisolated(unsafe) public static var protect: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path)
    }
    #endif

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
