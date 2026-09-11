import Foundation

@MainActor
final class StreamThrottle {
    private let interval: Duration
    private let onText: (String) -> Void
    private var pending = ""
    private var task: Task<Void, Never>?

    init(interval: Duration = .milliseconds(60), onText: @escaping @MainActor (String) -> Void) {
        self.interval = interval
        self.onText = onText
    }

    func receive(_ chunk: String) {
        pending += chunk
        guard task == nil else { return }
        task = Task { @MainActor in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            task = nil
            guard !pending.isEmpty else { return }
            let flushed = pending
            pending = ""
            onText(flushed)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        pending = ""
    }
}
