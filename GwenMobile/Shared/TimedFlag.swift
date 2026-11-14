import Combine

@MainActor
class TimedFlag<Value: Sendable>: ObservableObject {
    @Published private(set) var value: Value

    private let resetValue: Value
    private let duration: Duration
    private var expiry: Task<Void, Never>?

    init(_ value: Value, resetTo resetValue: Value, after duration: Duration) {
        self.value = value
        self.resetValue = resetValue
        self.duration = duration
    }

    func set(_ newValue: Value) {
        value = newValue
        expiry?.cancel()
        let duration = duration
        let resetValue = resetValue
        expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            self.value = resetValue
        }
    }
}
