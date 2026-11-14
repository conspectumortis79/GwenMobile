import GwenMobileKit
import Foundation

struct LocalModelManifest: Codable, Equatable, Sendable {
    var repo: String
    var bytes: Int64
    var name: String?
    var family: LocalModelFamily?
    var context: String?
    var vision: Bool?
    var tools: Bool?
    var parameterBillions: Double?
    var quantization: String?
    var source: LocalModelSource?
}

struct LocalModelFiles: Sendable {
    let root: URL

    init(root: URL = StoragePaths().support.appendingPathComponent("local-models", isDirectory: true)) {
        self.root = root
    }

    func directory(for id: String) -> URL {
        root.appendingPathComponent(Self.folderName(id), isDirectory: true)
    }

    func manifestURL(for id: String) -> URL {
        directory(for: id).appendingPathComponent("model.json")
    }

    func manifest(for id: String) -> LocalModelManifest? {
        guard let data = try? Data(contentsOf: manifestURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(LocalModelManifest.self, from: data)
    }

    func isInstalled(_ id: String) -> Bool {
        guard manifest(for: id) != nil else { return false }
        let folder = directory(for: id)
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.appendingPathComponent("config.json").path),
              manager.fileExists(atPath: folder.appendingPathComponent("tokenizer.json").path)
        else { return false }
        return weights(in: folder)
    }

    func installedIDs() -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        return names.compactMap { name in
            let folder = root.appendingPathComponent(name, isDirectory: true)
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("model.json")),
                  let manifest = try? JSONDecoder().decode(LocalModelManifest.self, from: data),
                  isInstalled(manifest.repo) else { return nil }
            return manifest.repo
        }
    }

    func installedChoices() -> [LocalModelChoice] {
        installedIDs().compactMap { id in
            if let choice = LocalCatalog.choice(for: id) { return choice }
            guard let manifest = manifest(for: id) else { return nil }
            return LocalCatalog.fallback(manifest: manifest, id: id)
        }
    }

    func write(_ manifest: LocalModelManifest, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: folder.appendingPathComponent("model.json"), options: .atomic)
    }

    func recoverInterruptedInstall() {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: root.path) else { return }
        for name in names {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            if name.hasSuffix(".partial") {
                try? manager.removeItem(at: folder)
                continue
            }
            guard let finalName = Self.finalName(ofInterrupted: name) else { continue }
            let final = root.appendingPathComponent(finalName, isDirectory: true)
            let finalComplete = manager.fileExists(atPath: final.path) && hasCompleteInstall(in: final)
            if finalComplete {
                try? manager.removeItem(at: folder)
            } else if hasCompleteInstall(in: folder) {
                if manager.fileExists(atPath: final.path) { try? manager.removeItem(at: final) }
                try? manager.moveItem(at: folder, to: final)
            } else {
                try? manager.removeItem(at: folder)
            }
        }
    }

    func remove(_ id: String) throws {
        let folder = directory(for: id)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    func partialDirectory(for id: String) -> URL {
        root.appendingPathComponent(Self.folderName(id) + ".partial", isDirectory: true)
    }

    static func folderName(_ id: String) -> String {
        let name = id.replacingOccurrences(of: "/", with: "--")
        guard !name.isEmpty, name != ".", name != ".." else {
            return "invalid-" + name.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
        }
        return name
    }

    private func hasCompleteInstall(in folder: URL) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.appendingPathComponent("model.json").path),
              manager.fileExists(atPath: folder.appendingPathComponent("config.json").path),
              manager.fileExists(atPath: folder.appendingPathComponent("tokenizer.json").path)
        else { return false }
        return weights(in: folder)
    }

    private static func finalName(ofInterrupted name: String) -> String? {
        guard let marker = name.range(of: ".old-", options: .backwards) else { return nil }
        let suffix = name[marker.upperBound...]
        guard suffix.count == 8, suffix.allSatisfy(\.isHexDigit) else { return nil }
        let final = String(name[..<marker.lowerBound])
        return final.isEmpty ? nil : final
    }

    private func weights(in folder: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else { return false }
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "safetensors",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > 0 { return true }
        }
        return false
    }
}

enum LocalModelDisk {
    static func availableBytes(at url: URL, creatingDirectory: Bool = false) -> Int64 {
        let manager = FileManager.default
        if creatingDirectory {
            try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values?.volumeAvailableCapacityForImportantUsage {
            return Int64(capacity)
        }
        let attributes = try? manager.attributesOfFileSystem(forPath: url.path)
        return (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }
}
