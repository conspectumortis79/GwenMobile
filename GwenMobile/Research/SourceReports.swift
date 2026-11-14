import GwenMobileKit
import Foundation

final class SourceReports: @unchecked Sendable {
    static let shared = SourceReports()

    private let defaults: UserDefaults
    private let key: String
    private let counts: LockedValue<[String: Int]>
    private let writeLock = NSLock()

    init(defaults: UserDefaults = .standard, key: String = SettingsKey.sourceReports) {
        self.defaults = defaults
        self.key = key
        let stored = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
        counts = LockedValue(stored)
    }

    static func normalized(_ domain: String) -> String {
        var name = domain.trimmed.lowercased()
        if name.hasPrefix("www.") { name.removeFirst(4) }
        return name
    }

    func count(_ domain: String) -> Int {
        counts.current[Self.normalized(domain)] ?? 0
    }

    func isReported(_ domain: String) -> Bool {
        count(domain) > 0
    }

    #if DEBUG
    var reportedDomains: [String] {
        counts.current.keys.sorted()
    }
    #endif

    func report(_ domain: String) {
        let name = Self.normalized(domain)
        guard !name.isEmpty else { return }
        writeLock.lock()
        defer { writeLock.unlock() }
        counts.mutate { $0[name, default: 0] += 1 }
        persist()
    }

    func withdraw(_ domain: String) {
        let name = Self.normalized(domain)
        writeLock.lock()
        defer { writeLock.unlock() }
        counts.mutate { $0.removeValue(forKey: name) }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(counts.current) else { return }
        defaults.set(data, forKey: key)
    }
}
