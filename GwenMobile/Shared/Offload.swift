import Foundation

public enum Offload {
    public static func run<T: Sendable>(priority: TaskPriority = .userInitiated,
                                 _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        let task = Task.detached(priority: priority) { () async throws -> T in
            try Task.checkCancellation()
            return try await body()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public static func orNil<T: Sendable>(priority: TaskPriority = .userInitiated,
                                   _ body: @escaping @Sendable () async throws -> T) async -> T? {
        try? await run(priority: priority, body)
    }

    public static func orNilFlat<T: Sendable>(priority: TaskPriority = .userInitiated,
                                       _ body: @escaping @Sendable () async throws -> T?) async -> T? {
        do {
            return try await run(priority: priority, body).flatMap { $0 }
        } catch {
            return nil
        }
    }

    public static func value<T: Sendable>(priority: TaskPriority = .userInitiated,
                                   _ body: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: priority) { body() }.value
    }
}
