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

    func write(_ manifest: LocalModelManifest, for id: String) throws {
        let folder = directory(for: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL(for: id), options: .atomic)
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
        id.replacingOccurrences(of: "/", with: "--")
    }

    private func weights(in folder: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return false
        }
        return names.contains { name in
            guard name.hasSuffix(".safetensors") else { return false }
            let path = folder.appendingPathComponent(name).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
            return (size ?? 0) > 0
        }
    }
}
