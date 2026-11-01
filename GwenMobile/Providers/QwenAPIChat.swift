import GwenMobileKit
import Foundation

extension QwenAPI {
    static func makeRequest(baseURL: String, key: String, model: String,
                            messages: [ChatMessage], imageData: [Data], videoData: [Data] = [],
                            stream: Bool = true, system: String? = nil,
                            thinking: ThinkingDirective,
                            extra: [String: Any] = [:]) throws -> URLRequest {
        let parts = try contentParts(messages: messages, imageData: imageData, videoData: videoData)
        let apiMessages: [[String: Any]] = [ChatPayload.system(system ?? SystemPrompt.chat())]
            + zip(messages, parts).map { m, c in
                ChatPayload.message(role: m.role, content: c)
            }
        return try ChatRequest.post(baseURL: baseURL, key: key, model: model, messages: apiMessages,
                                    stream: stream, thinking: thinking,
                                    timeout: APITimeout.chatRequest, accept: "application/json",
                                    extra: extra)
    }

    static func dataURL(_ data: Data) -> String? {
        guard let storable = MediaStore.apiData(data) else { return nil }
        return "data:\(PictureFormat.of(storable).mimeType);base64,\(storable.base64EncodedString())"
    }

    private static func contentParts(messages: [ChatMessage], imageData: [Data],
                                     videoData: [Data]) throws -> [Any] {
        var parts: [Any] = []
        var imgIdx = imageData.startIndex
        let lastUser = messages.lastIndex(where: { $0.role == .user })
        for (index, m) in messages.enumerated() {
            let carriesVideo = index == lastUser && !videoData.isEmpty
            if m.role == .user, !m.images.isEmpty || carriesVideo {
                let fallback = carriesVideo ? L.t("describe_video") : L.t("describe_images")
                var items: [[String: Any]] = [ChatPayload.text(m.text.isEmpty ? fallback : m.text)]
                for _ in m.images where imgIdx < imageData.endIndex {
                    guard let image = ChatPayload.image(imageData[imgIdx]) else {
                        throw APIError(message: L.t("image_too_large"))
                    }
                    items.append(image)
                    imgIdx += 1
                }
                if carriesVideo {
                    for data in videoData {
                        items.append(ChatPayload.video(data))
                    }
                }
                parts.append(items)
            } else {
                parts.append(m.text)
            }
        }
        return parts
    }

    static func askText(_ req: URLRequest) async throws -> String? {
        let data = try await HTTP.jsonData(req)
        return try await Offload.run {
            guard let obj = try? JSONDecoder().decode(ChatResponse.self, from: data) else { return nil }
            return obj.answerText
        }
    }

    static func resolveQuery(baseURL: String, key: String, model: String,
                             history: [ChatMessage], question: String? = nil, picture: Data? = nil,
                             thinking: ThinkingDirective) async throws -> String? {
        guard let last = (question ?? history.last(where: { $0.role == .user })?.text)?.trimmed,
              !last.isEmpty else {
            return nil
        }
        let text = FollowUpResolver.requestMessages(text: last, history: history).first?.text ?? last
        let request = try userRequest(baseURL: baseURL, key: key, model: model, text: text,
                                      picture: picture, thinking: thinking)
        let data = try await HTTP.jsonData(request)
        return try await Offload.run { FollowUpResolver.resolvedQuery(from: data) }
    }

    static func userRequest(baseURL: String, key: String, model: String, text: String,
                            picture: Data?, thinking: ThinkingDirective) throws -> URLRequest {
        var user: Any = text
        if let picture {
            guard let image = ChatPayload.image(picture) else {
                throw APIError(message: L.t("image_too_large"))
            }
            user = [ChatPayload.text(text), image]
        }
        return try ChatRequest.post(baseURL: baseURL, key: key, model: model,
                                    messages: [ChatPayload.system(Prompt.Research.followUpQuery()),
                                               ChatPayload.user(user)],
                                    stream: false, thinking: thinking, timeout: APITimeout.chatRequest,
                                    extra: ToolRouter.toolFields(maxTokens: FollowUpResolver.maxTokens,
                                                                 tools: ToolRouter.queryResolverTools(),
                                                                 toolChoice: ToolRouter.forcedChoice))
    }

}
