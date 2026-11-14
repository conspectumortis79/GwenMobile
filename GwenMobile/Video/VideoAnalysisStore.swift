import GwenMobileKit
import Foundation

final class VideoAnalysisStore: @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager
    private let compress: @Sendable (URL, URL) async throws -> Void
    private let inFlight = LockedValue<[String: Task<Data?, Never>]>([:])

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
        "ana_\(file).mp4"
    }

    func targetURL(for file: String) -> URL {
        directory.appendingPathComponent(Self.analysisName(for: file))
    }

    func data(for file: String, sourceURL: URL) async -> Data? {
        let sourceSize = byteSize(of: sourceURL)
        guard sourceSize > 0 else { return nil }
        if sourceSize <= VideoCompression.minimumSourceBytes {
            return fileManager.contents(atPath: sourceURL.path)
        }
        let target = targetURL(for: file)
        if isFresh(target, source: sourceURL), let cached = fileManager.contents(atPath: target.path) {
            return cached
        }
        let task = inFlight.mutate { tasks -> Task<Data?, Never> in
            if let existing = tasks[file] { return existing }
            let task = Task { [self] in
                await compressedData(file: file, sourceURL: sourceURL, sourceSize: sourceSize)
            }
            tasks[file] = task
            return task
        }
        let data = await task.value
        inFlight.mutate { $0[file] = nil }
        return data
    }

    func discard(_ files: [String]) {
        for file in files {
            try? fileManager.removeItem(at: targetURL(for: file))
        }
    }

    func prune(keeping sources: Set<String>) {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix("ana_") && name.hasSuffix(".mp4") {
            let source = String(name.dropFirst(4).dropLast(4))
            guard !sources.contains(source) else { continue }
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func compressedData(file: String, sourceURL: URL, sourceSize: Int) async -> Data? {
        let target = targetURL(for: file)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporary = directory.appendingPathComponent("tmp_\(UUID().uuidString).mp4")
            defer { try? fileManager.removeItem(at: temporary) }
            try await compress(sourceURL, temporary)
            let size = byteSize(of: temporary)
            guard size > 0, size < sourceSize else {
                return fileManager.contents(atPath: sourceURL.path)
            }
            try? fileManager.removeItem(at: target)
            try fileManager.moveItem(at: temporary, to: target)
            flowMark("VIDEO analyse komprimiert bytes=\(sourceSize)->\(size)")
            return fileManager.contents(atPath: target.path)
        } catch {
            flowMark("VIDEO analyse komprimierung fehlgeschlagen fallback=original")
            return fileManager.contents(atPath: sourceURL.path)
        }
    }

    private func isFresh(_ target: URL, source: URL) -> Bool {
        guard let targetAttributes = try? fileManager.attributesOfItem(atPath: target.path),
              let targetDate = targetAttributes[.modificationDate] as? Date,
              byteSize(of: target) > 0,
              let sourceAttributes = try? fileManager.attributesOfItem(atPath: source.path),
              let sourceDate = sourceAttributes[.modificationDate] as? Date else {
            return false
        }
        return targetDate >= sourceDate
    }

    private func byteSize(of url: URL) -> Int {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }
}
