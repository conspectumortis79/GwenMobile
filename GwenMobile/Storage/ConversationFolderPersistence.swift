import GwenMobileKit
import Foundation

struct ConversationFolderPersistence: ConversationPersisting {
    static let markerName = "imported"
    static let fileExtension = "json"
    nonisolated(unsafe) static var manager: FileManager = .default

    let folder: URL
    let files: ConversationFilePersistence
    let onWrite: (@Sendable (UUID) -> Void)?

    private let written = LockedValue([UUID: Conversation]())

    init(folder: URL, legacy: ConversationFilePersistence,
         onWrite: (@Sendable (UUID) -> Void)? = nil) {
        self.folder = folder
        self.files = legacy
        self.onWrite = onWrite
    }

    func persist(_ conversations: [Conversation]) async throws {
        let folder = self.folder
        let written = self.written
        let onWrite = self.onWrite
        try await Offload.run {
            let manager = Self.manager
            let encoder = JSONEncoder()
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Self.markImported(folder, manager: manager)
            var kept = Set<String>()
            for conversation in conversations {
                let name = Self.fileName(conversation.id)
                kept.insert(name)
                guard written.current[conversation.id] != conversation else { continue }
                let data = try encoder.encode(conversation)
                let url = folder.appendingPathComponent(name)
                ConversationFilePersistence.keepPreviousCopy(at: url, as: url.appendingPathExtension("bak"),
                                                             with: manager)
                try data.write(to: url, options: .atomic)
                written.mutate { $0[conversation.id] = conversation }
                onWrite?(conversation.id)
            }
            if let names = try? manager.contentsOfDirectory(atPath: folder.path) {
                for name in names {
                    guard name.hasSuffix("." + Self.fileExtension), !kept.contains(name) else { continue }
                    let url = folder.appendingPathComponent(name)
                    try manager.removeItem(at: url)
                    let backup = url.appendingPathExtension("bak")
                    if manager.fileExists(atPath: backup.path) {
                        do { try manager.removeItem(at: backup) } catch {
                            flowLog.error("HISTORIE sicherung loeschen fehlgeschlagen datei=\(backup.lastPathComponent, privacy: .public)")
                        }
                    }
                    if let id = UUID(uuidString: String(name.dropLast(Self.fileExtension.count + 1))) {
                        written.mutate { $0[id] = nil }
                    }
                }
            }
        }
    }

    func load() -> ConversationLoad {
        if let result = loadFolder() { return result }
        switch files.load() {
        case .nothing:
            return .nothing
        case .loaded(let stored):
            migrate(stored)
            return .loaded(stored)
        case .recovered(let stored, let preserved):
            migrate(stored)
            return .recovered(stored, preserved: preserved)
        case .quarantined(let url):
            return .quarantined(url)
        }
    }

    static func fileName(_ id: UUID) -> String {
        id.uuidString + "." + fileExtension
    }

    private enum ReadOutcome {
        case intact(Conversation, Data)
        case damaged(Conversation, URL)
        case unreadable(URL)
    }

    private func loadFolder() -> ConversationLoad? {
        let manager = Self.manager
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let names = try? manager.contentsOfDirectory(atPath: folder.path) else { return nil }
        let stored = names.filter { $0.hasSuffix("." + Self.fileExtension) }.sorted()
        guard !stored.isEmpty || names.contains(Self.markerName) else { return nil }
        guard !stored.isEmpty else { return .nothing }
        var loaded: [Conversation] = []
        var preserved: URL?
        for name in stored {
            switch readOne(folder.appendingPathComponent(name)) {
            case .intact(let conversation, _):
                loaded.append(conversation)
                written.mutate { $0[conversation.id] = conversation }
            case .damaged(let conversation, let copy):
                loaded.append(conversation)
                if preserved == nil { preserved = copy }
            case .unreadable(let copy):
                if preserved == nil { preserved = copy }
            }
        }
        if loaded.isEmpty {
            var target = folder
            if let preserved { target = preserved }
            return .quarantined(target)
        }
        if let preserved { return .recovered(loaded, preserved: preserved) }
        return .loaded(loaded)
    }

    private func readOne(_ url: URL) -> ReadOutcome {
        if let data = files.read(url) {
            let issues = DecodeIssues()
            if let conversation = ConversationFilePersistence.decodeOne(data, issues: issues) {
                guard issues.isDamaged else { return .intact(conversation, data) }
                flowLog.error("HISTORIE felder unlesbar datei=\(url.lastPathComponent, privacy: .public)")
                let backup = files.aside(url, as: .backup)
                if let repaired = try? JSONEncoder().encode(conversation) {
                    try? repaired.write(to: url, options: .atomic)
                    written.mutate { $0[conversation.id] = conversation }
                }
                return .damaged(conversation, backup)
            }
        }
        if let copyData = files.read(url.appendingPathExtension("bak")),
           let conversation = ConversationFilePersistence.decodeOne(copyData) {
            flowLog.error("HISTORIE aus sicherungskopie gelesen datei=\(url.lastPathComponent, privacy: .public)")
            return .damaged(conversation, files.aside(url, as: .quarantine))
        }
        flowLog.error("HISTORIE unlesbar datei=\(url.lastPathComponent, privacy: .public)")
        return .unreadable(files.aside(url, as: .quarantine))
    }

    private func migrate(_ conversations: [Conversation]) {
        let manager = Self.manager
        let parent = folder.deletingLastPathComponent()
        cleanLeftovers(in: parent, manager: manager)
        let staging = parent.appendingPathComponent("\(folder.lastPathComponent).import-\(UUID().uuidString.prefix(8))")
        let backup = parent.appendingPathComponent("\(folder.lastPathComponent).old-\(UUID().uuidString.prefix(8))")
        var movedOld = false
        do {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            for conversation in conversations {
                let data = try encoder.encode(conversation)
                try data.write(to: staging.appendingPathComponent(Self.fileName(conversation.id)),
                                options: .atomic)
                written.mutate { $0[conversation.id] = conversation }
            }
            try Self.markImported(staging, manager: manager)
            if manager.fileExists(atPath: folder.path) {
                try manager.moveItem(at: folder, to: backup)
                movedOld = true
            }
            do {
                try manager.moveItem(at: staging, to: folder)
            } catch {
                if movedOld, !manager.fileExists(atPath: folder.path) {
                    do { try manager.moveItem(at: backup, to: folder) } catch {
                        flowLog.error("HISTORIE umzug wiederherstellen fehlgeschlagen \(error.localizedDescription, privacy: .public)")
                    }
                }
                throw error
            }
            if movedOld {
                do { try manager.removeItem(at: backup) } catch {
                    flowLog.error("HISTORIE alte ablage entfernen fehlgeschlagen \(error.localizedDescription, privacy: .public)")
                }
            }
            flowLog.info("HISTORIE in einzeldateien umgezogen anzahl=\(conversations.count, privacy: .public)")
            cleanLeftovers(in: parent, manager: manager)
        } catch {
            if manager.fileExists(atPath: folder.path) {
                try? manager.removeItem(at: staging)
            }
            flowLog.error("HISTORIE umzug in einzeldateien fehlgeschlagen \(error.localizedDescription)")
        }
    }

    private func cleanLeftovers(in parent: URL, manager: FileManager) {
        let prefix = folder.lastPathComponent + ".import-"
        if let names = try? manager.contentsOfDirectory(atPath: parent.path) {
            for name in names where name.hasPrefix(prefix) {
                let url = parent.appendingPathComponent(name)
                let complete = manager.fileExists(atPath: url.appendingPathComponent(Self.markerName).path)
                if !manager.fileExists(atPath: folder.path), complete { continue }
                try? manager.removeItem(at: url)
            }
        }
    }

    private static func markImported(_ folder: URL, manager: FileManager) throws {
        let marker = folder.appendingPathComponent(markerName)
        guard !manager.fileExists(atPath: marker.path) else { return }
        try Data().write(to: marker, options: .atomic)
    }
}
