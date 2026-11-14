import GwenMobileKit
import Foundation

@MainActor
final class ChatRunner {
    static let shared = ChatRunner()

    private var live: [(id: Int, task: Task<String, Error>)] = []
    private var issued = 0
    private let stream: @Sendable (URLRequest) -> AsyncThrowingStream<String, Error>

    init(stream: @escaping @Sendable (URLRequest) -> AsyncThrowingStream<String, Error> = QwenAPI.streamText) {
        self.stream = stream
    }

    func run(_ req: URLRequest, onChunk: @escaping @MainActor (String) -> Void) async throws -> String {
        let runner = stream
        let t = Task { () -> String in
            var full = ""
            do {
                for try await chunk in runner(req) {
                    full += chunk
                    onChunk(chunk)
                }
                return full
            } catch let e as APIError {
                var err = e
                err.recoveredText = full.isEmpty ? nil : full
                throw err
            } catch {
                throw APIError(message: error.localizedDescription, recoveredText: full.isEmpty ? nil : full)
            }
        }
        issued += 1
        let id = issued
        live.append((id: id, task: t))
        defer { live.removeAll { $0.id == id } }
        return try await withTaskCancellationHandler {
            try await t.value
        } onCancel: {
            t.cancel()
        }
    }

    func cancelAll() { live.forEach { $0.task.cancel() } }
}
