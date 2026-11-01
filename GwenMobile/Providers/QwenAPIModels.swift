import GwenMobileKit
import Foundation

extension QwenAPI {
    static func fetchModelsRequest(baseURL: String, key: String) throws -> URLRequest {
        try HTTP.authorizedGET(baseURL: baseURL, path: APIEndpoint.models, key: key,
                               timeout: APITimeout.modelsRequest)
    }

    static func fetchModels(baseURL: String, key: String) async throws -> [String] {
        let req = try fetchModelsRequest(baseURL: baseURL, key: key)
        let (data, resp) = try await HTTP.data(req)
        try HTTP.ensureAPISuccess(resp, data: data)
        return try await Offload.run {
            try JSONDecoder().decode(ModelsPayload.self, from: data).data.map(\.id).sorted()
        }
    }

}
