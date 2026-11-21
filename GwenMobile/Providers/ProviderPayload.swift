import GwenMobileKit
import Foundation

enum ProviderPayload {
    static func fetch<Value: Decodable & Sendable>(request: URLRequest) async throws -> Value {
        let data = try await HTTP.jsonData(request)
        return try await Offload.run { try JSONDecoder().decode(Value.self, from: data) }
    }
}
