import GwenMobileKit
import Foundation

enum ScanSaver {
    @discardableResult
    static func storeInDownloads(_ file: AttachedFile, documents: DocumentStore) -> URL? {
        guard let source = documents.storedURL(for: file.file) else { return nil }
        let folder = documents.paths.downloads
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = uniqueURL(in: folder, name: file.name)
            try manager.copyItem(at: source, to: target)
            flowMark("SCAN dateien name=\(target.lastPathComponent)")
            return target
        } catch {
            flowLog.error("SCAN dateien fehler=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func uniqueURL(in folder: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let candidate: (Int?) -> URL = { index in
            guard let index else { return folder.appendingPathComponent(name) }
            return folder.appendingPathComponent(ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)")
        }
        return FreeName.first(candidate, upTo: .max, isTaken: FreeName.exists) ?? candidate(nil)
    }
}
