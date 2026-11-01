import Foundation

@MainActor
protocol IdleCountdown: AnyObject {
    func restart(after interval: Duration, expiring: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class TaskIdleCountdown: IdleCountdown {
    private var work: Task<Void, Never>?

    func restart(after interval: Duration, expiring: @escaping @MainActor () -> Void) {
        work?.cancel()
        work = Task { @MainActor in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            expiring()
        }
    }

    func cancel() {
        work?.cancel()
        work = nil
    }
}

struct GalleryProgress: Equatable {
    let total: Int
    var done: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(min(done, total)) / Double(total)
    }
}

enum GalleryResult: Equatable {
    case saved(Int)
    case denied
    case failed
}

@MainActor
final class GalleryOperation: ObservableObject {
    @Published private(set) var saving: GalleryProgress?
    @Published private(set) var searching: Set<UUID> = []
    @Published private(set) var result: GalleryResult?

    private let idle: IdleCountdown
    private let resultLifetime: Duration

    init(idle: IdleCountdown = TaskIdleCountdown(), resultLifetime: Duration = NoticeLine.defaultLifetime) {
        self.idle = idle
        self.resultLifetime = resultLifetime
    }

    var showsBar: Bool { saving != nil || result != nil }

    func isSearching(_ message: UUID?) -> Bool {
        guard let message else { return false }
        return searching.contains(message)
    }

    func beginSearch(_ message: UUID) {
        searching.insert(message)
    }

    func endSearch(_ message: UUID) {
        searching.remove(message)
    }

    func beginSaving(total: Int) {
        result = nil
        idle.cancel()
        saving = GalleryProgress(total: total, done: 0)
    }

    func advanceSaving() {
        guard let saving, saving.done < saving.total else { return }
        self.saving = GalleryProgress(total: saving.total, done: saving.done + 1)
    }

    func finishSaving(_ outcome: PhotosWriteOutcome) {
        saving = nil
        switch outcome {
        case .saved(let count): show(.saved(count))
        case .denied: show(.denied)
        case .failed: show(.failed)
        }
    }

    func clearResult() {
        result = nil
        idle.cancel()
    }

    private func show(_ next: GalleryResult) {
        result = next
        idle.restart(after: resultLifetime) { [weak self] in self?.result = nil }
    }
}
