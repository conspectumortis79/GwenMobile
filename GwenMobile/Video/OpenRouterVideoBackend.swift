import GwenMobileKit
import Foundation

enum OpenRouterVideoAPI: VideoJobAPIKind {
    static let resolution = "720p"
    nonisolated(unsafe) static var pollInterval = Duration.seconds(10)

    struct Job: VideoJobState {
        var id: String
        var status: String
        var error: String?

        var failureText: String? { error }
    }

    static func createRequest(baseURL: String, key: String, model: String,
                              request: VideoRequest, sourceVideo: Data?) throws -> URLRequest {
        let url = try HTTP.requiredURL(baseURL, videosPath)
        return try HTTP.jsonPOST(url: url, key: key,
                                 body: body(model: model, request: request, sourceVideo: sourceVideo),
                                 timeout: APITimeout.videoRequest)
    }

    static func body(model: String, request: VideoRequest, sourceVideo: Data?) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "prompt": request.prompt,
            "duration": request.clampedDuration,
            "aspect_ratio": request.ratio.rawValue,
            "resolution": resolution,
        ]
        if let sourceVideo {
            body["input_references"] = [[
                "type": "video_url",
                "video_url": ["url": dataURL(sourceVideo)],
            ]]
        }
        return body
    }

    static func dataURL(_ data: Data) -> String {
        "data:\(VideoBytes.mimeType(data));base64,\(data.base64EncodedString())"
    }
}

struct OpenRouterVideoBackend: VideoGenerating {
    func generate(baseURL: String, key: String, model: String,
                  request: VideoRequest, sourceVideo: Data?) async throws -> GeneratedVideo {
        if let sourceVideo {
            flowMark("VIDEO quelle bytes=\(sourceVideo.count)")
        }
        return try await OpenRouterVideoAPI.generate(baseURL: baseURL, key: key, model: model,
                                                     request: request, sourceVideo: sourceVideo)
    }
}
