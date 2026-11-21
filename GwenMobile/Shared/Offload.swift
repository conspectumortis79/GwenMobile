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

    public static func window<Outcome: Sendable>(
        count: Int,
        limit: Int,
        isolation: isolated (any Actor)? = #isolation,
        work: @escaping @Sendable (Int) async -> Outcome,
        onResult: (Outcome) -> Void
    ) async {
        guard count > 0 else { return }
        let width = max(1, min(count, limit))
        await withTaskGroup(of: Outcome.self) { group in
            var launched = 0
            func launchNext() {
                let index = launched
                launched += 1
                group.addTask { await work(index) }
            }
            while launched < width {
                launchNext()
            }
            for await outcome in group {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                onResult(outcome)
                guard launched < count else { continue }
                launchNext()
            }
        }
    }
}
