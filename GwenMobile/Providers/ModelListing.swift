import GwenMobileKit
import Foundation

struct ModelListingResult: Equatable, Sendable {
    var models: [String]
    var imageModels: [String]
    var videoGenerationModels: [String] = []
}

protocol ModelListing: Sendable {
    func list(baseURL: String, key: String) async throws -> ModelListingResult
}

struct OpenAIModelLister: ModelListing {
    func list(baseURL: String, key: String) async throws -> ModelListingResult {
        let models = try await QwenAPI.fetchModels(baseURL: baseURL, key: key)
        return ModelListingResult(models: models,
                                  imageModels: ModelFilter.imageCandidates(models),
                                  videoGenerationModels: ModelFilter.videoGenerationCandidates(models))
    }
}
