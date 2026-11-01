import GwenMobileKit
import Foundation

enum OpenAIVideoAPI {
    static let videosPath = "/videos"
    static let modelsPath = "/videos/models"
    nonisolated(unsafe) static var pollInterval = Duration.seconds(10)
    static let maximumPolls = 60

    struct ModelList: Decodable, Sendable {
        struct Entry: Decodable, Sendable {
            var id: String
        }

        var data: [Entry]
    }

    struct Job: Decodable, Sendable {
        struct Failure: Decodable, Sendable {
            var message: String?
        }

        var id: String
        var status: String
        var error: Failure?
    }

    enum Phase: Equatable, Sendable {
        case pending
        case running
        case succeeded
        case failed(String)
    }

    static func modelsRequest(baseURL: String, key: String) throws -> URLRequest {
        try HTTP.authorizedGET(baseURL: baseURL, path: modelsPath, key: key,
                               timeout: APITimeout.modelsRequest)
    }

    static func modelIDs(from data: Data) throws -> [String] {
        try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id).sorted()
    }

    static func fetchModelIDs(baseURL: String, key: String) async throws -> [String] {
        let data = try await HTTP.jsonData(modelsRequest(baseURL: baseURL, key: key))
        return try await Offload.run { try modelIDs(from: data) }
    }

    static func createRequest(baseURL: String, key: String, model: String,
                              request: VideoRequest) throws -> URLRequest {
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

    static func jobID(from data: Data) throws -> String {
        let job = try JSONDecoder().decode(Job.self, from: data)
        guard !job.id.isEmpty else { throw APIError(message: L.t("video_start_failed")) }
        return job.id
    }

    static func phase(from data: Data) throws -> Phase {
        let job = try JSONDecoder().decode(Job.self, from: data)
        switch job.status.lowercased() {
        case "pending", "queued": return .pending
        case "in_progress", "running": return .running
        case "completed", "succeeded": return .succeeded
        case "failed", "cancelled", "canceled", "expired":
            let detail = job.error?.message?.trimmed ?? ""
            return .failed(detail.isEmpty ? L.t("video_generation_failed") : detail)
        default:
            throw APIError(message: L.t("video_timeout"))
        }
    }

    static func jobRequest(baseURL: String, key: String, id: String) throws -> URLRequest {
        try HTTP.authorizedGET(baseURL: baseURL, path: videosPath + "/" + id, key: key,
                               timeout: APITimeout.videoRequest)
    }

    static func contentRequest(baseURL: String, key: String, id: String) throws -> URLRequest {
        try HTTP.authorizedGET(baseURL: baseURL, path: videosPath + "/" + id + "/content", key: key,
                               timeout: APITimeout.videoDownload)
    }

    static func download(baseURL: String, key: String, id: String) async throws -> Data {
        let data = try await HTTP.jsonData(contentRequest(baseURL: baseURL, key: key, id: id))
        guard data.count <= VideoPolicy.maxBytes, VideoBytes.isVideo(data) else {
            throw APIError(message: L.t("video_download_failed"))
        }
        return data
    }
}

struct OpenAIVideoBackend: VideoGenerating {
    func generate(baseURL: String, key: String, model: String,
                  request: VideoRequest, sourceVideo: Data?) async throws -> GeneratedVideo {
        guard sourceVideo == nil else {
            throw APIError(message: L.t("video_edit_unsupported"))
        }
        let create = try OpenAIVideoAPI.createRequest(baseURL: baseURL, key: key, model: model,
                                                      request: request)
        let created = try await HTTP.jsonData(create)
        let jobID = try await Offload.run { try OpenAIVideoAPI.jobID(from: created) }
        flowMark("VIDEO auftrag task=\(jobID) model=\(model)")
        var polls = 0
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: OpenAIVideoAPI.pollInterval)
            polls += 1
            guard polls <= OpenAIVideoAPI.maximumPolls else {
                throw APIError(message: L.t("video_timeout"))
            }
            let job = try await HTTP.jsonData(try OpenAIVideoAPI.jobRequest(baseURL: baseURL, key: key,
                                                                            id: jobID))
            let phase = try await Offload.run { try OpenAIVideoAPI.phase(from: job) }
            switch phase {
            case .pending, .running:
                flowMark("VIDEO warten task=\(jobID) runde=\(polls)")
            case .succeeded:
                flowMark("VIDEO fertig task=\(jobID) runde=\(polls)")
                let data = try await OpenAIVideoAPI.download(baseURL: baseURL, key: key, id: jobID)
                return GeneratedVideo(data: data)
            case .failed(let message):
                throw APIError(message: message)
            }
        }
    }
}
