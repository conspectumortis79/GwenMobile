import GwenMobileKit
import Foundation

struct StoredDocument: Sendable {
    let file: String
    let bytes: Int
    let url: URL
}

final class DocumentStore: @unchecked Sendable {
    static let filePrefix = "doc_"

    let paths: StoragePaths

    private let storage: FileStorage

    init(paths: StoragePaths = StoragePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        storage = FileStorage(layout: DocumentLayout(paths: paths), fileManager: fileManager)
    }

    func prepareDirectories() { storage.prepare() }

    func store(url: URL) -> StoredDocument? {
        let name = storage.layout.newName(url.pathExtension.lowercased())
        guard let bytes = storage.copy(from: url, as: name) else { return nil }
        return StoredDocument(file: name, bytes: bytes, url: storage.url(for: name))
    }

    func store(data: Data, fileExtension: String) -> StoredDocument? {
        let name = storage.layout.newName(fileExtension.lowercased())
        guard let bytes = storage.write(data, as: name) else { return nil }
        return StoredDocument(file: name, bytes: bytes, url: storage.url(for: name))
    }

    func storedURL(for file: String) -> URL? { storage.storedURL(for: file) }

    func data(named file: String) -> Data? { storage.data(for: file) }

    func text(named file: String) -> String? { storage.sidecarText(for: file) }

    func writeText(_ text: String, for file: String) { storage.writeSidecar(text, for: file) }

    func byteSize(of file: String) -> Int { storage.byteSize(of: file) }

    func discardStored(_ files: [String]) { storage.discard(files) }

    func fileNames() -> [String] { storage.names() }

    @discardableResult
    func moveFilesToTrash(_ files: [String]) -> [TrashedFile] { storage.moveToTrash(files) }

    func discardTrashed(_ trashed: [TrashedFile]) { storage.discardTrashed(trashed) }

    func restoreFromTrash(_ trashed: [TrashedFile]) { storage.restoreFromTrash(trashed) }
}
