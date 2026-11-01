import GwenMobileKit
import Foundation

enum VideoWishCheck {
    static let maxTokens = 200

    private struct Answer: Decodable {
        var video: Bool
        var prompt: String?
        var duration: Int?
        var ratio: String?
    }

    static func request(baseURL: String, key: String, model: String, wish: String,
                        thinking: ThinkingDirective) throws -> URLRequest {
        try ChatRequest.post(baseURL: baseURL, key: key, model: model,
                             messages: [ChatPayload.system(PromptLibrary.text("check_video_intent")),
                                        ChatPayload.user(wish)],
                             stream: false, thinking: thinking, timeout: APITimeout.chatRequest,
                             extra: ["max_tokens": maxTokens])
    }

    static func classify(asking ask: () async throws -> String?, fallback: String) async -> VideoRequest? {
        guard let answer = try? await ask() else { return nil }
        return parse(answer, fallback: fallback)
    }

    static func parse(_ answer: String?, fallback: String) -> VideoRequest? {
        guard let answer, let decoded = JSONFragment.decode(Answer.self, from: answer), decoded.video else {
            return nil
        }
        let prompt = (decoded.prompt?.trimmed).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        guard !prompt.isEmpty else { return nil }
        return VideoRequest(prompt: prompt,
                            duration: decoded.duration ?? VideoRequest.defaultDuration,
                            ratio: decoded.ratio.flatMap(VideoRatio.init(rawValue:)) ?? .landscape)
    }
}
