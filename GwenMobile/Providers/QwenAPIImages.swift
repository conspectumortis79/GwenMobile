import GwenMobileKit
import Foundation

extension QwenAPI {
    static func composeImagePromptRequest(baseURL: String, key: String, model: String,
                                          instruction: String, history: [ChatMessage],
                                          pictures: Int = 1,
                                          thinking: ThinkingDirective) throws -> URLRequest {
        try makeRequest(baseURL: baseURL, key: key, model: model,
                        messages: ImagePromptComposer.requestMessages(text: instruction, history: history),
                        imageData: [], stream: false,
                        system: Prompt.Research.imagePrompt(pictures: pictures),
                        thinking: thinking,
                        extra: ToolRouter.toolFields(maxTokens: ImagePromptComposer.maxTokens,
                                                     tools: ToolRouter.imagePromptTools(),
                                                     toolChoice: ToolRouter.forcedChoice))
    }

    static func composeImagePrompt(baseURL: String, key: String, model: String,
                                   instruction: String,
                                   history: [ChatMessage],
                                   pictures: Int = 1,
                                   thinking: ThinkingDirective) async throws -> String? {
        let request = try composeImagePromptRequest(baseURL: baseURL, key: key, model: model,
                                                    instruction: instruction, history: history,
                                                    pictures: pictures, thinking: thinking)
        let data = try await HTTP.jsonData(request)
        return try await Offload.run {
            ImagePromptComposer.usablePrompt(ImagePromptComposer.prompt(from: data),
                                            insteadOf: instruction)
        }
    }

    static func makeImageRequest(baseURL: String, key: String, model: String,
                                 prompt: String, inputImages: [Data],
                                 isEdit: Bool = false) throws -> URLRequest {
        let url = try HTTP.chatCompletionsURL(baseURL)
        var parts: [[String: Any]] = []
        for data in inputImages {
            guard let url = dataURL(data) else { throw APIError(message: L.t("image_too_large")) }
            parts.append(["image": url])
        }
        parts.append(["text": ImagePromptFrame.framed(prompt, inputImages: inputImages.count, isEdit: isEdit)])
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": parts]],
        ]
        return try HTTP.jsonPOST(url: url, key: key, body: body, timeout: APITimeout.imageRequest)
    }

    static func generateImage(req: URLRequest) async throws -> [URL] {
        let (data, resp) = try await HTTP.data(req)
        try HTTP.ensureAPISuccess(resp, data: data)
        let parsed = try await Offload.run { () -> (urls: [URL], note: String?) in
            guard let obj = try? JSONDecoder().decode(ChatResponse.self, from: data),
                  let content = obj.answerParts else {
                throw APIError(message: L.t("no_image"))
            }
            var urls: [URL] = []
            var note: String?
            for part in content {
                if let s = part.image, let u = URL(string: s) { urls.append(u) }
                if urls.isEmpty, let t = part.text, !t.trimmingCharacters(in: .whitespaces).isEmpty {
                    note = t
                }
            }
            return (urls, note)
        }
        guard !parsed.urls.isEmpty else { throw APIError(message: parsed.note ?? L.t("no_image")) }
        return parsed.urls
    }

    static func download(_ url: URL) async throws -> Data {
        guard url.scheme == "https", url.host != nil else {
            throw APIError(message: L.t("pictures_insecure"))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = APITimeout.imageDownload
        let (data, resp) = try await HTTP.data(request)
        try HTTP.ensureSuccess(resp)
        guard ImageBytes.isPicture(data) else {
            throw APIError(message: L.t("pictures_not_a_picture"))
        }
        return data
    }

}
