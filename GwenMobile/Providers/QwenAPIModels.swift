import GwenMobileKit
import Foundation

extension QwenAPI {
    static func fetchModelsRequest(baseURL: String, key: String) throws -> URLRequest {
        try IDModelList.request(baseURL: baseURL, path: APIEndpoint.models, key: key)
    }

    static func fetchModels(baseURL: String, key: String) async throws -> [String] {
        try await IDModelList.fetchIDs(baseURL: baseURL, path: APIEndpoint.models, key: key)
    }
}
