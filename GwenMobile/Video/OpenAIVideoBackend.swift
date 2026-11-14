import GwenMobileKit
import Foundation

enum OpenAIVideoAPI: VideoJobAPIKind {
    nonisolated(unsafe) static var pollInterval = Duration.seconds(10)

    struct Job: VideoJobState {
        struct Failure: Decodable, Sendable {
            var message: String?
        }

        var id: String
        var status: String
        var error: Failure?

        var failureText: String? { error?.message }
    }

    static func createRequest(baseURL: String, key: String, model: String,
                              request: VideoRequest, sourceVideo: Data?) throws -> URLRequest {
        guard sourceVideo == nil else {
            throw APIError(message: L.t("video_edit_unsupported"))
        }
        let url = try HTTP.requiredURL(baseURL, videosPath)
        return try HTTP.jsonPOST(url: url, key: key,
                                 body: body(model: model, request: request),
                                 timeout: APITimeout.videoRequest)
    }

    static func body(model: String, request: VideoRequest) -> [String: Any] {
        [
            "model": model,
            "prompt": request.prompt,
            "seconds": seconds(request.clampedDuration),
            "size": size(request.ratio),
        ]
    }

    static func seconds(_ duration: Int) -> String {
        switch duration {
        case ...6: return "4"
        case 7...10: return "8"
        default: return "12"
        }
    }

    static func size(_ ratio: VideoRatio) -> String {
        switch ratio {
        case .landscape, .square, .fourThree: return "1280x720"
        case .portrait, .threeFour: return "720x1280"
        }
    }
}

struct OpenAIVideoBackend: VideoGenerating {
    func generate(baseURL: String, key: String, model: String,
                  request: VideoRequest, sourceVideo: Data?) async throws -> GeneratedVideo {
        try await OpenAIVideoAPI.generate(baseURL: baseURL, key: key, model: model,
                                          request: request, sourceVideo: sourceVideo)
    }
}
