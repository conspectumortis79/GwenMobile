import Foundation

enum Offload {
    static func run<T: Sendable>(priority: TaskPriority = .userInitiated,
                                 _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await Task.detached(priority: priority, operation: body).value
    }
}
