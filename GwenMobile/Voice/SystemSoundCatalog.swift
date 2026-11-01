import GwenMobileKit
import Foundation

struct SystemSound: Equatable, Hashable, Sendable, Identifiable {
    let path: String
    let name: String
    let folder: String

    var id: String { path }
}

struct SystemSoundCatalog: Sendable {
    static let liveRoots = ["/System/Library/Audio/UISounds", "/System/Library/Sounds"]
    static let playable: Set<String> = ["caf", "aiff", "aif", "wav", "m4a", "mp3"]

    let root: URL

    static func live(roots: [String] = liveRoots, fileManager: FileManager = .default) -> SystemSoundCatalog? {
        roots.lazy.map { URL(fileURLWithPath: $0, isDirectory: true) }
            .first { fileManager.isReadableFile(atPath: $0.path) }
            .map(SystemSoundCatalog.init(root:))
    }

    func sounds(fileManager: FileManager = .default) -> [SystemSound] {
        guard let walker = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                  options: [.skipsHiddenFiles]) else { return [] }
        var found: [SystemSound] = []
        for case let url as URL in walker where Self.playable.contains(url.pathExtension.lowercased()) {
            found.append(SystemSound(path: url.path, name: Self.name(of: url),
                                     folder: Self.folder(of: url, under: root)))
        }
        return found.sorted { ($0.folder, $0.name.lowercased()) < ($1.folder, $1.name.lowercased()) }
    }

    static func name(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    static func folder(of url: URL, under root: URL) -> String {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let base = root.standardizedFileURL.path
        guard parent.hasPrefix(base) else { return "" }
        return String(parent.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func name(ofPath path: String) -> String {
        name(of: URL(fileURLWithPath: path))
    }
}
