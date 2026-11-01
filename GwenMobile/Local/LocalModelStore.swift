import GwenMobileKit
import Foundation

enum LocalModelPhase: Equatable, Sendable {
    case absent
    case downloading
    case installed
    case failed(String)

    var isDownloading: Bool { self == .downloading }
}

struct LocalModelStatus: Equatable, Sendable {
    var phase: LocalModelPhase = .absent
    var received: Int64 = 0
    var total: Int64 = 0

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(received) / Double(total)))
    }
}

@MainActor
final class LocalModelStore: ObservableObject {
    static let shared = LocalModelStore()

    @Published private(set) var statuses: [String: LocalModelStatus] = [:]
    @Published private(set) var freeBytes: Int64 = 0
    @Published private(set) var memoryLabel: String = LocalMemory.label
    @Published private(set) var huggingFace: [LocalModelChoice] = []
    @Published private(set) var huggingFaceLoading = false
    @Published private(set) var huggingFaceError: String?

    let files: LocalModelFiles
    private var installed: [LocalModelChoice] = []
    private var running: [String: (token: UUID, task: Task<Void, Never>)] = [:]

    init(files: LocalModelFiles = LocalModelFiles()) {
        self.files = files
        try? FileManager.default.createDirectory(at: files.root, withIntermediateDirectories: true)
        refresh()
    }

    var choices: [LocalModelChoice] {
        var seen = Set<String>()
        var result: [LocalModelChoice] = []
        for choice in installed + huggingFace
        where seen.insert(choice.id).inserted {
            result.append(choice)
        }
        return result
    }

    func choice(for id: String) -> LocalModelChoice? {
        choices.first { $0.id == id } ?? LocalCatalog.choice(for: id)
    }

    func refresh() {
        installed = files.installedChoices()
        let known = Set(installed.map(\.id))
        var next: [String: LocalModelStatus] = [:]
        for choice in choices {
            if known.contains(choice.id) {
                next[choice.id] = LocalModelStatus(phase: .installed, received: choice.bytes,
                                                   total: choice.bytes)
            } else if let current = statuses[choice.id], current.phase.isDownloading {
                next[choice.id] = current
            } else if let current = statuses[choice.id], case .failed(let message) = current.phase {
                next[choice.id] = LocalModelStatus(phase: .failed(message), received: 0, total: 0)
            } else {
                next[choice.id] = LocalModelStatus(phase: .absent, received: 0, total: choice.bytes)
            }
        }
        statuses = next
        freeBytes = availableBytes()
        memoryLabel = LocalMemory.label
    }

    func status(for choice: LocalModelChoice) -> LocalModelStatus {
        statuses[choice.id] ?? LocalModelStatus(phase: .absent, received: 0, total: choice.bytes)
    }

    func searchHuggingFace() async {
        guard !huggingFaceLoading else { return }
        huggingFaceLoading = true
        huggingFaceError = nil
        let task = Task { try await HuggingFaceMLXCatalog().discover() }
        do {
            let found = try await task.value
            huggingFace = found
            LocalCatalog.register(found + files.installedChoices())
            refresh()
        } catch {
            huggingFaceError = error.localizedDescription
        }
        huggingFaceLoading = false
    }

    func download(_ choice: LocalModelChoice) async {
        guard !(statuses[choice.id]?.phase.isDownloading ?? false) else { return }
        statuses[choice.id] = LocalModelStatus(phase: .downloading, received: 0, total: choice.bytes)
        let downloader = LocalModelDownloader(files: files)
        let store = self
        let token = UUID()
        let task = Task {
            do {
                let manifest = try await downloader.install(choice) { received, total in
                    Task { @MainActor in
                        store.update(choice, received: received, total: total)
                    }
                }
                store.installed = store.files.installedChoices()
                store.statuses[choice.id] = LocalModelStatus(phase: .installed, received: manifest.bytes,
                                                             total: manifest.bytes)
                store.freeBytes = store.availableBytes()
                LocalCatalog.register(store.huggingFace + store.installed)
            } catch is CancellationError {
                store.statuses[choice.id] = LocalModelStatus(phase: .absent, received: 0, total: choice.bytes)
            } catch {
                store.statuses[choice.id] = LocalModelStatus(phase: .failed(error.localizedDescription),
                                                             received: 0, total: choice.bytes)
            }
        }
        running[choice.id] = (token, task)
        await task.value
        if running[choice.id]?.token == token {
            running[choice.id] = nil
        }
    }

    func cancel(_ choiceID: String) {
        running[choiceID]?.task.cancel()
    }

    @discardableResult
    func delete(_ choice: LocalModelChoice) -> Bool {
        do {
            try files.remove(choice.id)
        } catch {
            flowLog.error("MODELL loeschen fehlgeschlagen id=\(choice.id, privacy: .public) fehler=\(error.localizedDescription, privacy: .public)")
            refresh()
            return false
        }
        installed.removeAll { $0.id == choice.id }
        statuses[choice.id] = LocalModelStatus(phase: .absent, received: 0, total: choice.bytes)
        if choice.source == .huggingFace {
            huggingFace.removeAll { $0.id == choice.id }
            LocalCatalog.register(huggingFace + installed)
        }
        freeBytes = availableBytes()
        return true
    }

    func isInstalled(_ choice: LocalModelChoice) -> Bool {
        installed.contains { $0.id == choice.id }
    }

    func installedChoices() -> [LocalModelChoice] {
        installed
    }

    private func update(_ choice: LocalModelChoice, received: Int64, total: Int64) {
        statuses[choice.id] = LocalModelStatus(phase: .downloading, received: received,
                                               total: max(total, choice.bytes))
    }

    private func availableBytes() -> Int64 {
        let values = try? files.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values?.volumeAvailableCapacityForImportantUsage {
            return Int64(capacity)
        }
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: files.root.path)
        return (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }
}
