import Foundation

public struct StoragePaths: Sendable {
    public static let sidecarPrefix = "txt_"

    public let documents: URL
    public let support: URL

    public init(documents: URL? = nil, support: URL? = nil, fileManager: FileManager = .default) {
        let docs = documents ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let derived: URL
        if let support {
            derived = support
        } else if documents != nil {
            derived = docs.appendingPathComponent("Library/Application Support", isDirectory: true)
        } else {
            derived = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? docs
        }
        self.documents = docs
        self.support = derived
    }

    public var images: URL { support.appendingPathComponent("images", isDirectory: true) }
    public var trash: URL { support.appendingPathComponent(".trash", isDirectory: true) }
    public var answers: URL { documents.appendingPathComponent("answers", isDirectory: true) }
    public var code: URL { documents.appendingPathComponent("code", isDirectory: true) }
    public var downloads: URL { documents.appendingPathComponent("Downloads", isDirectory: true) }
    public var ocr: URL { support.appendingPathComponent("ocr", isDirectory: true) }
    public var conversations: URL { support.appendingPathComponent("conversations.json") }
    public var conversationsFolder: URL { support.appendingPathComponent("conversations", isDirectory: true) }
    public var memory: URL { support.appendingPathComponent("memory.json") }
    public var watches: URL { support.appendingPathComponent("price_watches.json") }
    public var files: URL { support.appendingPathComponent("files", isDirectory: true) }
    public var storedConversationsBeforeMove: URL { documents.appendingPathComponent("conversations.json") }
    public var storedImagesBeforeMove: URL { documents.appendingPathComponent("images", isDirectory: true) }
    public var storedTrashBeforeMove: URL { documents.appendingPathComponent(".trash", isDirectory: true) }
    public var storedOCRBeforeMove: URL { documents.appendingPathComponent("ocr", isDirectory: true) }
    public var apiKeySeed: URL { documents.appendingPathComponent("seed_api_key.txt") }
    public var providerSeed: URL { documents.appendingPathComponent("seed_provider.json") }

    public func image(_ name: String) -> URL { images.appendingPathComponent(name) }
    public func file(_ name: String) -> URL { files.appendingPathComponent(name) }
    public func fileText(_ name: String) -> URL { files.appendingPathComponent(Self.sidecarPrefix + name) }
    public func trashItem(_ name: String) -> URL { trash.appendingPathComponent(name) }
    public func trashedFileText(_ name: String) -> URL { trashItem(Self.sidecarPrefix + name) }

    public func moveSharedFoldersIntoAppStorage(_ manager: FileManager = .default) {
        moveContents(of: storedImagesBeforeMove, into: images, with: manager)
        moveContents(of: storedTrashBeforeMove, into: trash, with: manager)
    }

    private func moveContents(of source: URL, into destination: URL, with manager: FileManager) {
        guard source.path != destination.path else { return }
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let names = try? manager.contentsOfDirectory(atPath: source.path) else { return }
        try? manager.createDirectory(at: destination, withIntermediateDirectories: true)
        var emptied = true
        for name in names {
            let target = destination.appendingPathComponent(name)
            guard !manager.fileExists(atPath: target.path) else { emptied = false; continue }
            do { try manager.moveItem(at: source.appendingPathComponent(name), to: target) }
            catch { emptied = false }
        }
        guard emptied else { return }
        do {
            try manager.removeItem(at: source)
        } catch {
            flowLog.error("UMZUG altordner bleibt name=\(source.lastPathComponent, privacy: .public)")
        }
    }
}
