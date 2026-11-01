import GwenMobileKit
import Foundation

struct TrashedFile: Equatable, Sendable {
    let file: String
    let trashed: String
    var bytes: Int = 0
}

protocol StoredFileLayout: Sendable {
    var directory: URL { get }
    var trashDirectory: URL { get }
    var prefix: String { get }
    func stored(_ name: String) -> URL
    func trashed(_ name: String) -> URL
    func sidecar(of name: String) -> URL?
    func trashedSidecar(of name: String) -> URL?
}

extension StoredFileLayout {
    func trashed(_ name: String) -> URL { trashDirectory.appendingPathComponent(name) }

    func newName(_ ext: String) -> String {
        let base = "\(prefix)\(UUID().uuidString.prefix(12))"
        return ext.isEmpty ? base : "\(base).\(ext)"
    }
}

struct ImageLayout: StoredFileLayout {
    let paths: StoragePaths

    var directory: URL { paths.images }
    var trashDirectory: URL { paths.trash }
    var prefix: String { MediaStore.filePrefix }

    func stored(_ name: String) -> URL { paths.image(name) }
    func sidecar(of name: String) -> URL? { nil }
    func trashedSidecar(of name: String) -> URL? { nil }
}

struct DocumentLayout: StoredFileLayout {
    let paths: StoragePaths

    var directory: URL { paths.files }
    var trashDirectory: URL { paths.trash }
    var prefix: String { DocumentStore.filePrefix }

    func stored(_ name: String) -> URL { paths.file(name) }
    func sidecar(of name: String) -> URL? { paths.fileText(name) }
    func trashedSidecar(of name: String) -> URL? { paths.trashedFileText(name) }
}

struct FileStorage {
    let layout: any StoredFileLayout
    let fileManager: FileManager

    init(layout: any StoredFileLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    func prepare() {
        do {
            try fileManager.createDirectory(at: layout.directory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: layout.trashDirectory, withIntermediateDirectories: true)
        } catch {
            flowLog.error("ABLAGE vorbereiten fehlgeschlagen \(error.localizedDescription, privacy: .public)")
        }
    }

    func url(for name: String) -> URL { layout.stored(name) }

    func exists(_ name: String) -> Bool { fileManager.fileExists(atPath: layout.stored(name).path) }

    func storedURL(for name: String) -> URL? { exists(name) ? layout.stored(name) : nil }

    func data(for name: String) -> Data? { fileManager.contents(atPath: layout.stored(name).path) }

    func names() -> [String] {
        do {
            return try fileManager.contentsOfDirectory(atPath: layout.directory.path)
                .filter { $0.hasPrefix(layout.prefix) }
        } catch {
            flowLog.error("ABLAGE auflisten fehlgeschlagen \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func byteSize(of name: String) -> Int {
        let attrs = try? fileManager.attributesOfItem(atPath: layout.stored(name).path)
        return (attrs?[.size] as? NSNumber)?.intValue ?? 0
    }

    func sidecarText(for name: String) -> String? {
        guard let url = layout.sidecar(of: name), let data = fileManager.contents(atPath: url.path) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func writeSidecar(_ text: String, for name: String) {
        guard let url = layout.sidecar(of: name), let data = text.data(using: .utf8) else { return }
        do {
            try data.write(to: url)
        } catch {
            flowLog.error("ABLAGE begleittext schreiben fehlgeschlagen datei=\(url.lastPathComponent, privacy: .public)")
        }
    }

    func discard(_ names: [String]) {
        for name in names {
            remove(layout.stored(name))
            if let sidecar = layout.sidecar(of: name) { remove(sidecar) }
        }
    }

    @discardableResult
    func moveToTrash(_ names: [String]) -> [TrashedFile] {
        var moved: [TrashedFile] = []
        for name in names {
            guard exists(name) else { continue }
            let target = "\(UUID().uuidString.prefix(8))_\(name)"
            let bytes = byteSize(of: name)
            do {
                try fileManager.moveItem(at: layout.stored(name), to: layout.trashed(target))
                moveSidecar(of: name, to: target)
                moved.append(TrashedFile(file: name, trashed: target, bytes: bytes))
            } catch {
                flowLog.error("ABLAGE verschieben fehlgeschlagen datei=\(name, privacy: .public)")
            }
        }
        return moved
    }

    func restoreFromTrash(_ trashed: [TrashedFile]) {
        for entry in trashed {
            move(from: layout.trashed(entry.trashed), to: layout.stored(entry.file))
            guard let from = layout.trashedSidecar(of: entry.trashed),
                  let to = layout.sidecar(of: entry.file),
                  fileManager.fileExists(atPath: from.path) else { continue }
            move(from: from, to: to)
        }
    }

    func discardTrashed(_ trashed: [TrashedFile]) {
        for entry in trashed {
            remove(layout.trashed(entry.trashed))
            if let sidecar = layout.trashedSidecar(of: entry.trashed) { remove(sidecar) }
        }
    }

    func emptyTrash() {
        let entries: [String]
        do {
            entries = try fileManager.contentsOfDirectory(atPath: layout.trashDirectory.path)
        } catch {
            flowLog.error("ABLAGE papierkorb lesen fehlgeschlagen \(error.localizedDescription, privacy: .public)")
            return
        }
        for entry in entries { remove(layout.trashed(entry)) }
    }

    func write(_ data: Data, as name: String) -> Int? {
        do {
            try data.write(to: layout.stored(name), options: [.atomic])
            return data.count
        } catch {
            flowLog.error("ABLAGE schreiben fehlgeschlagen datei=\(name, privacy: .public)")
            return nil
        }
    }

    func copy(from url: URL, as name: String) -> Int? {
        let target = layout.stored(name)
        do {
            if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
            try fileManager.copyItem(at: url, to: target)
            return byteSize(of: name)
        } catch {
            flowLog.error("DATEI ablage fehlgeschlagen \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func moveSidecar(of name: String, to target: String) {
        guard let from = layout.sidecar(of: name), let to = layout.trashedSidecar(of: target),
              fileManager.fileExists(atPath: from.path) else { return }
        move(from: from, to: to)
    }

    private func remove(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            flowLog.error("ABLAGE löschen fehlgeschlagen datei=\(url.lastPathComponent, privacy: .public)")
        }
    }

    private func move(from: URL, to: URL) {
        guard fileManager.fileExists(atPath: from.path) else { return }
        do {
            try fileManager.moveItem(at: from, to: to)
        } catch {
            flowLog.error("ABLAGE verschieben fehlgeschlagen datei=\(from.lastPathComponent, privacy: .public)")
        }
    }
}
