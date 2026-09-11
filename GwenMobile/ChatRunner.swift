import Foundation

@MainActor
final class ChatRunner {
    static let shared = ChatRunner()
    private var task: Task<String, Error>?

    func run(_ req: URLRequest, onChunk: @escaping @MainActor (String) -> Void) async throws -> String {
        let t = Task { () -> String in
            var full = ""
            do {
                for try await chunk in QwenAPI.streamText(req: req) {
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
        task = t
        defer { task = nil }
        return try await t.value
    }

    func cancel() { task?.cancel() }
}