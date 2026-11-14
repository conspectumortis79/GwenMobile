import GwenMobileKit
import Foundation

enum GeneratedPicture: Equatable, Sendable {
    case remote(URL)
    case inline(Data)
}

protocol ImageGenerating: Sendable {
    func generate(baseURL: String, key: String, model: String, prompt: String,
                  inputImages: [Data], isEdit: Bool) async throws -> [GeneratedPicture]
}

enum ImagePromptFrame {
    static func framed(_ prompt: String, inputImages: Int, isEdit: Bool) -> String {
        guard isEdit, inputImages > 0 else { return prompt }
        return L.fmt(inputImages == 1 ? "edit_frame" : "edit_frame_multi", prompt)
    }
}

struct DashScopeImageBackend: ImageGenerating {
    func generate(baseURL: String, key: String, model: String, prompt: String,
                  inputImages: [Data], isEdit: Bool) async throws -> [GeneratedPicture] {
        let request = try QwenAPI.makeImageRequest(baseURL: baseURL, key: key, model: model,
                                                   prompt: prompt, inputImages: inputImages, isEdit: isEdit)
        return try await QwenAPI.generateImage(req: request).map(GeneratedPicture.remote)
    }
}
