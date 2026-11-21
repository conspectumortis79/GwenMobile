import GwenMobileKit
import Foundation

struct IDModelList: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        var id: String
    }

    var data: [Entry]

    static func ids(from data: Data) throws -> [String] {
        try JSONDecoder().decode(IDModelList.self, from: data).data.map(\.id).sorted()
    }

    static func request(baseURL: String, path: String, key: String) throws -> URLRequest {
        try HTTP.authorizedGET(baseURL: baseURL, path: path, key: key,
                               timeout: APITimeout.modelsRequest)
    }

    static func fetchIDs(baseURL: String, path: String, key: String) async throws -> [String] {
        let data = try await HTTP.jsonData(request(baseURL: baseURL, path: path, key: key))
        return try await Offload.run { try ids(from: data) }
    }
}

struct ModelListingResult: Equatable, Sendable {
    var models: [String]
    var imageModels: [String]
    var videoGenerationModels: [String] = []

    static func built(models: [String], imageModels: [String]? = nil,
                      videoModels: [String] = []) -> ModelListingResult {
        ModelListingResult(models: models,
                           imageModels: imageModels ?? ModelFilter.imageCandidates(models),
                           videoGenerationModels: videoModels.isEmpty
                               ? ModelFilter.videoGenerationCandidates(models)
                               : videoModels)
    }
}

protocol ModelListing: Sendable {
    func list(baseURL: String, key: String) async throws -> ModelListingResult
}

struct OpenAIModelLister: ModelListing {
    func list(baseURL: String, key: String) async throws -> ModelListingResult {
        ModelListingResult.built(models: try await QwenAPI.fetchModels(baseURL: baseURL, key: key))
    }
}
