import Foundation

public final class LockedValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public var current: Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func set(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    @discardableResult public func exchange(_ newValue: Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        let previous = value
        value = newValue
        return previous
    }

    @discardableResult public func mutate<Outcome>(_ body: (inout Value) -> Outcome) -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

public final class LockedDictionary<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Key: Value] = [:]
    private var insertionOrder: [Key] = []
    private let capacity: Int

    public init(capacity: Int = .max) {
        self.capacity = max(1, capacity)
    }

    public func value(for key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func setValue(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        if values.updateValue(value, forKey: key) == nil {
            insertionOrder.append(key)
        }
        while insertionOrder.count > capacity {
            let oldest = insertionOrder.removeFirst()
            values[oldest] = nil
        }
    }

    public func removeValue(for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = nil
        insertionOrder.removeAll { $0 == key }
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        values = [:]
        insertionOrder = []
    }
}
