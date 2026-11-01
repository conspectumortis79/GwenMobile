import GwenMobileKit
import Foundation

enum ConversationLoad: Equatable {
    case nothing
    case loaded([Conversation])
    case recovered([Conversation], preserved: URL)
    case quarantined(URL)
}

protocol ConversationPersisting: Sendable {
    func persist(_ conversations: [Conversation]) async throws
    func load() -> ConversationLoad
}

struct ConversationFilePersistence: ConversationPersisting {
    let url: URL
    let legacyURL: URL?
    let stamp: @Sendable () -> String

    init(url: URL, legacyURL: URL? = nil,
         stamp: @escaping @Sendable () -> String = { Formatters.fileStamp(Date()) }) {
        self.url = url
        self.legacyURL = legacyURL
        self.stamp = stamp
    }

    var backup: URL { url.appendingPathExtension("bak") }

    func persist(_ conversations: [Conversation]) async throws {
        let url = self.url
        let backup = self.backup
        try await Offload.run {
            let manager = FileManager.default
            let data = try JSONEncoder().encode(conversations)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            Self.keepPreviousCopy(at: url, as: backup, with: manager)
            try data.write(to: url, options: .atomic)
        }
    }

    func load() -> ConversationLoad {
        adoptLegacyStore()
        let data = read(url).flatMap { $0.isEmpty ? nil : $0 } ?? legacyURL.flatMap { read($0) }
        guard let data, !data.isEmpty else { return .nothing }
        let issues = DecodeIssues()
        if let conversations = Self.decode(data, issues: issues) {
            guard issues.isDamaged else { return .loaded(conversations) }
            let damaged = issues.damagedFields
            flowLog.error("HISTORIE felder unlesbar felder=\(damaged, privacy: .public)")
            let preserved = aside(url, as: .backup)
            if let repaired = try? JSONEncoder().encode(conversations) {
                try? repaired.write(to: url, options: .atomic)
            }
            return .recovered(conversations, preserved: preserved)
        }
        if let backupData = read(backup), let earlier = Self.decode(backupData) {
            flowLog.error("HISTORIE aus sicherungskopie gelesen anzahl=\(earlier.count, privacy: .public)")
            let preserved = aside(url, as: .quarantine)
            try? backupData.write(to: url, options: .atomic)
            return .recovered(earlier, preserved: preserved)
        }
        flowLog.error("HISTORIE unlesbar datei=\(url.lastPathComponent, privacy: .public)")
        return .quarantined(aside(url, as: .quarantine))
    }

    func read(_ at: URL) -> Data? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: at.path) else { return nil }
        do {
            return try Data(contentsOf: at)
        } catch {
            flowLog.error("HISTORIE lesen fehlgeschlagen datei=\(at.lastPathComponent, privacy: .public) \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func decodeOne(_ data: Data?, issues: DecodeIssues? = nil) -> Conversation? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        if let issues, let key = DecodeIssues.userInfoKey { decoder.userInfo[key] = issues }
        return try? decoder.decode(Conversation.self, from: data)
    }

    private static func decode(_ data: Data?, issues: DecodeIssues? = nil) -> [Conversation]? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        if let issues, let key = DecodeIssues.userInfoKey { decoder.userInfo[key] = issues }
        return try? decoder.decode([Conversation].self, from: data)
    }

    private func adoptLegacyStore() {
        let manager = FileManager.default
        guard let legacyURL, !manager.fileExists(atPath: url.path),
              Self.hasReadableBytes(at: legacyURL, with: manager) else { return }
        do {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            flowLog.error("HISTORIE umzug vorbereiten fehlgeschlagen \(error.localizedDescription, privacy: .public)")
            return
        }
        guard (try? manager.moveItem(at: legacyURL, to: url)) != nil else {
            flowLog.error("HISTORIE umzug abgelehnt von=\(legacyURL.lastPathComponent, privacy: .public)")
            return
        }
        flowLog.info("HISTORIE umgezogen in den anwendungsspeicher")
    }

    static func hasReadableBytes(at url: URL, with manager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        return true
    }

    enum AsideKind {
        case quarantine
        case backup

        var marker: String { self == .quarantine ? "corrupt" : "unlesbar" }
        var failureLabel: String { self == .quarantine ? "quarantaene" : "sicherung" }

        func apply(_ manager: FileManager, from at: URL, to target: URL) throws {
            switch self {
            case .quarantine: try manager.moveItem(at: at, to: target)
            case .backup: try manager.copyItem(at: at, to: target)
            }
        }
    }

    func aside(_ at: URL, as kind: AsideKind) -> URL {
        let manager = FileManager.default
        let target = stampedCopy(of: at, marker: kind.marker)
        do {
            try kind.apply(manager, from: at, to: target)
        } catch {
            flowLog.error("HISTORIE \(kind.failureLabel) fehlgeschlagen datei=\(at.lastPathComponent, privacy: .public)")
            return at
        }
        return target
    }

    func stampedCopy(of at: URL, marker: String) -> URL {
        let stamp = self.stamp()
        func named(_ suffix: String) -> URL { at.appendingPathExtension("\(marker)-\(stamp)\(suffix)") }
        return FreeName.first({ named($0.map { "-\($0)" } ?? "") }, upTo: 99, isTaken: FreeName.exists)
            ?? named("-\(UUID().uuidString.prefix(8))")
    }

    static func keepPreviousCopy(at url: URL, as backup: URL, with manager: FileManager) {
        guard hasReadableBytes(at: url, with: manager) else { return }
        do {
            if manager.fileExists(atPath: backup.path) { try manager.removeItem(at: backup) }
            try manager.copyItem(at: url, to: backup)
        } catch {
            flowLog.error("HISTORIE sicherungskopie fehlgeschlagen \(error.localizedDescription, privacy: .public)")
        }
    }
}
