import GwenMobileKit
import Foundation

enum OpenRouterImageAPI {
    static let imagesPath = "/images"
    static let imageModelsPath = "/images/models"
    static let referenceType = "image_url"

    static func request(baseURL: String, key: String, model: String, prompt: String,
                        inputImages: [Data], isEdit: Bool) throws -> URLRequest {
        let url = try HTTP.requiredURL(baseURL, imagesPath)
        var body: [String: Any] = [
            "model": model,
            "prompt": ImagePromptFrame.framed(prompt, inputImages: inputImages.count, isEdit: isEdit),
            "n": 1,
        ]
        if !inputImages.isEmpty {
            var references: [[String: Any]] = []
            for data in inputImages {
                guard let url = QwenAPI.dataURL(data) else {
                    throw APIError(message: L.t("image_too_large"))
                }
                references.append([
                    "type": referenceType,
                    "image_url": ["url": url],
                ])
            }
            body["input_references"] = references
        }
        return try HTTP.jsonPOST(url: url, key: key, body: body, timeout: APITimeout.imageRequest)
    }

    static func pictures(from data: Data) throws -> [Data] {
        let decoded = try JSONDecoder().decode(ImageResponse.self, from: data)
        let pictures = decoded.data.compactMap { entry in entry.b64JSON.flatMap { Data(base64Encoded: $0) } }
        guard !pictures.isEmpty else { throw APIError(message: L.t("no_image")) }
        return pictures
    }

    struct ImageResponse: Decodable, Sendable {
        struct Entry: Decodable, Sendable {
            var b64JSON: String?

            enum CodingKeys: String, CodingKey {
                case b64JSON = "b64_json"
            }
        }

        var data: [Entry]
    }
}

struct OpenRouterImageBackend: ImageGenerating {
    func generate(baseURL: String, key: String, model: String, prompt: String,
                  inputImages: [Data], isEdit: Bool) async throws -> [GeneratedPicture] {
        let request = try OpenRouterImageAPI.request(baseURL: baseURL, key: key, model: model, prompt: prompt,
                                                     inputImages: inputImages, isEdit: isEdit)
        let data = try await HTTP.jsonData(request)
        return try await Offload.run { try OpenRouterImageAPI.pictures(from: data) }.map(GeneratedPicture.inline)
    }
}

struct OpenRouterModelLister: ModelListing {
    func list(baseURL: String, key: String) async throws -> ModelListingResult {
        let models = try await QwenAPI.fetchModels(baseURL: baseURL, key: key)
        let imageModels = try? await IDModelList.fetchIDs(baseURL: baseURL,
                                                          path: OpenRouterImageAPI.imageModelsPath,
                                                          key: key)
        let videoModels = (try? await OpenRouterVideoAPI.fetchModelIDs(baseURL: baseURL, key: key)) ?? []
        return ModelListingResult.built(models: models, imageModels: imageModels, videoModels: videoModels)
    }
}
