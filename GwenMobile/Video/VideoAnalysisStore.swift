import GwenMobileKit
import Foundation

final class VideoAnalysisStore: @unchecked Sendable {
    private struct Transfer {
        let token: UUID
        let task: Task<Data?, Never>
    }

    private let directory: URL
    private let fileManager: FileManager
    private let compress: @Sendable (URL, URL) async throws -> Void
    private let inFlight = LockedValue<[String: Transfer]>([:])
    private let failed = LockedValue<Set<String>>([])
    private let activeTemporaries = LockedValue<Set<String>>([])

    private static let analysisPrefix = "ana_"
    private static let analysisSuffix = ".mp4"
    private static let originalPrefix = "org_"
    private static let temporaryPrefix = "tmp_"

    init(directory: URL,
         fileManager: FileManager = .default,
         compress: @escaping @Sendable (URL, URL) async throws -> Void = { source, target in
             try await VideoCompression.export(from: source, to: target)
         }) {
        self.directory = directory
        self.fileManager = fileManager
        self.compress = compress
    }

    func prepare() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func analysisName(for file: String) -> String {
        analysisPrefix + file + analysisSuffix
    }

    static func originalMarkName(for file: String) -> String {
        originalPrefix + file
    }

    static func sourceName(ofCached name: String) -> String? {
        if name.hasPrefix(analysisPrefix), name.hasSuffix(analysisSuffix) {
            return String(name.dropFirst(analysisPrefix.count).dropLast(analysisSuffix.count))
        }
        if name.hasPrefix(originalPrefix) { return String(name.dropFirst(originalPrefix.count)) }
        return nil
    }

    func targetURL(for file: String) -> URL {
        directory.appendingPathComponent(Self.analysisName(for: file))
    }

    func originalMarkURL(for file: String) -> URL {
        directory.appendingPathComponent(Self.originalMarkName(for: file))
    }

    func data(for file: String, sourceURL: URL) async -> Data? {
        let sourceSize = byteSize(of: sourceURL)
        guard sourceSize > 0 else { return nil }
        if sourceSize <= VideoCompression.minimumSourceBytes || keepsOriginal(file, source: sourceURL) {
            return fileManager.contents(atPath: sourceURL.path)
        }
        let target = targetURL(for: file)
        if isFresh(target, source: sourceURL), let cached = fileManager.contents(atPath: target.path) {
            return cached
        }
        var token: UUID?
        let transfer = inFlight.mutate { tasks -> Transfer in
            if let existing = tasks[file] { return existing }
            let made = Transfer(token: UUID(), task: Task { [self] in
                await compressedData(file: file, sourceURL: sourceURL, sourceSize: sourceSize)
            })
            tasks[file] = made
            token = made.token
            return made
        }
        let data = await transfer.task.value
        if let token {
            inFlight.mutate { tasks in
                if tasks[file]?.token == token { tasks[file] = nil }
            }
        }
        return data
    }

    func discard(_ files: [String]) {
        let running = inFlight.mutate { tasks -> [Task<Data?, Never>] in
            files.compactMap { tasks.removeValue(forKey: $0)?.task }
        }
        for task in running { task.cancel() }
        for file in files {
            try? fileManager.removeItem(at: targetURL(for: file))
            try? fileManager.removeItem(at: originalMarkURL(for: file))
        }
        failed.mutate { $0.subtract(files) }
    }

    func prune(keeping sources: Set<String>) {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where isOrphaned(name, keeping: sources) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func isOrphaned(_ name: String, keeping sources: Set<String>) -> Bool {
        if name.hasPrefix(Self.temporaryPrefix) { return !activeTemporaries.current.contains(name) }
        guard let source = Self.sourceName(ofCached: name) else { return false }
        return !sources.contains(source)
    }

    private func keepsOriginal(_ file: String, source: URL) -> Bool {
        failed.current.contains(file) || isCurrent(originalMarkURL(for: file), against: source)
    }

    private func keepOriginal(_ file: String, sourceSize: Int, exportedSize: Int) {
        fileManager.createFile(atPath: originalMarkURL(for: file).path, contents: nil)
        flowMark("VIDEO analyse nicht kleiner bytes=\(sourceSize)->\(exportedSize) original bleibt")
    }

    private func compressedData(file: String, sourceURL: URL, sourceSize: Int) async -> Data? {
        let target = targetURL(for: file)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporaryName = Self.temporaryPrefix + UUID().uuidString + Self.analysisSuffix
            let temporary = directory.appendingPathComponent(temporaryName)
            activeTemporaries.mutate { $0.insert(temporaryName) }
            defer {
                try? fileManager.removeItem(at: temporary)
                activeTemporaries.mutate { $0.remove(temporaryName) }
            }
            try await compress(sourceURL, temporary)
            let size = byteSize(of: temporary)
            guard size > 0 else { throw VideoCompressionError.empty }
            guard size < sourceSize else {
                keepOriginal(file, sourceSize: sourceSize, exportedSize: size)
                return fileManager.contents(atPath: sourceURL.path)
            }
            try Task.checkCancellation()
            try? fileManager.removeItem(at: target)
            try fileManager.moveItem(at: temporary, to: target)
            try? fileManager.removeItem(at: originalMarkURL(for: file))
            flowMark("VIDEO analyse komprimiert bytes=\(sourceSize)->\(size)")
            return fileManager.contents(atPath: target.path)
        } catch {
            if error is CancellationError || Task.isCancelled { return nil }
            failed.mutate { $0.insert(file) }
            flowMark("VIDEO analyse komprimierung fehlgeschlagen fallback=original")
            return fileManager.contents(atPath: sourceURL.path)
        }
    }

    private func isFresh(_ target: URL, source: URL) -> Bool {
        byteSize(of: target) > 0 && isCurrent(target, against: source)
    }

    private func isCurrent(_ url: URL, against source: URL) -> Bool {
        guard let date = modificationDate(of: url), let sourceDate = modificationDate(of: source) else {
            return false
        }
        return date >= sourceDate
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func byteSize(of url: URL) -> Int {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }
}
