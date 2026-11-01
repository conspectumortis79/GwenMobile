import GwenMobileKit
import Foundation

enum ExportFolder: String, CaseIterable, Equatable, Sendable {
    case answers
    case code
}

struct TrashedExport: Equatable, Sendable {
    let file: String
    let trashed: String
    let folder: ExportFolder
    var bytes: Int = 0
}

struct ExportLayout: StoredFileLayout {
    let paths: StoragePaths
    let folder: ExportFolder

    var directory: URL {
        switch folder {
        case .answers: return paths.answers
        case .code: return paths.code
        }
    }

    var trashDirectory: URL { paths.trash }
    var prefix: String { "" }

    func stored(_ name: String) -> URL { directory.appendingPathComponent(name) }
    func sidecar(of name: String) -> URL? { nil }
    func trashedSidecar(of name: String) -> URL? { nil }
}

final class ExportStore: @unchecked Sendable {
    private let paths: StoragePaths
    private let fileManager: FileManager
    private let ordered: [(folder: ExportFolder, storage: FileStorage)]

    init(paths: StoragePaths = StoragePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        ordered = ExportFolder.allCases.map { folder in
            (folder, FileStorage(layout: ExportLayout(paths: paths, folder: folder), fileManager: fileManager))
        }
    }

    func prepareDirectories() {
        for (_, storage) in ordered { storage.prepare() }
    }

    func countedFiles() -> Int {
        ExportFolder.allCases.reduce(0) { $0 + names(in: $1).count }
    }

    func countedBytes() -> Int {
        sizes().values.reduce(0) { total, table in total + table.values.reduce(0, +) }
    }

    func sizes() -> [ExportFolder: [String: Int]] {
        var table: [ExportFolder: [String: Int]] = [:]
        for (folder, storage) in ordered {
            var found: [String: Int] = [:]
            for name in names(in: folder) { found[name] = storage.byteSize(of: name) }
            table[folder] = found
        }
        return table
    }

    @discardableResult
    func moveAllToTrash() -> [TrashedExport] {
        var moved: [TrashedExport] = []
        for (folder, storage) in ordered {
            for entry in storage.moveToTrash(names(in: folder)) {
                moved.append(TrashedExport(file: entry.file, trashed: entry.trashed, folder: folder,
                                           bytes: entry.bytes))
            }
        }
        return moved
    }

    func restoreFromTrash(_ trashed: [TrashedExport]) {
        for entry in trashed {
            storage(for: entry.folder)?.restoreFromTrash([TrashedFile(file: entry.file, trashed: entry.trashed)])
        }
    }

    func discardTrashed(_ trashed: [TrashedExport]) {
        for entry in trashed {
            storage(for: entry.folder)?.discardTrashed([TrashedFile(file: entry.file, trashed: entry.trashed)])
        }
    }

    private func storage(for folder: ExportFolder) -> FileStorage? {
        ordered.first { $0.folder == folder }?.storage
    }

    private func names(in folder: ExportFolder) -> [String] {
        let directory = ExportLayout(paths: paths, folder: folder).directory
        let entries = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])) ?? []
        return entries.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.map(\.lastPathComponent)
    }
}

extension ExportStore: StorageInventory {}
