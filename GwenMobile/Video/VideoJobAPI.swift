import GwenMobileKit
import Foundation

enum VideoJobPhase: Equatable, Sendable {
    case pending
    case running
    case succeeded
    case failed(String)

    init(job: some VideoJobState) throws {
        switch job.status.lowercased() {
        case "pending", "queued": self = .pending
        case "in_progress", "running": self = .running
        case "completed", "succeeded": self = .succeeded
        case "failed", "cancelled", "canceled", "expired":
            let detail = job.failureText?.trimmed ?? ""
            self = .failed(detail.isEmpty ? L.t("video_generation_failed") : detail)
        default:
            throw APIError(message: L.t("video_timeout"))
        }
    }
}

protocol VideoJobState: Decodable, Sendable {
    var id: String { get }
    var status: String { get }
    var failureText: String? { get }
}

protocol VideoJobAPIKind: Sendable {
    associatedtype Job: VideoJobState
    static var pollInterval: Duration { get }
    static func createRequest(baseURL: String, key: String, model: String,
                              request: VideoRequest, sourceVideo: Data?) throws -> URLRequest
}

struct VideoModelList: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        var id: String
    }

    var data: [Entry]
}

extension VideoJobAPIKind {
    static var videosPath: String { "/videos" }
    private static var modelsPath: String { "/videos/models" }
    private static var maximumPolls: Int { 60 }

    static func modelsRequest(baseURL: String, key: String) throws -> URLRequest {
        try HTTP.authorizedGET(baseURL: baseURL, path: modelsPath, key: key,
                               timeout: APITimeout.modelsRequest)
    }

    static func modelIDs(from data: Data) throws -> [String] {
        try JSONDecoder().decode(VideoModelList.self, from: data).data.map(\.id).sorted()
    }

    static func fetchModelIDs(baseURL: String, key: String) async throws -> [String] {
        let data = try await HTTP.jsonData(modelsRequest(baseURL: baseURL, key: key))
        return try await Offload.run { try modelIDs(from: data) }
    }

    static func jobID(from data: Data) throws -> String {
        let job = try JSONDecoder().decode(Job.self, from: data)
        guard !job.id.isEmpty else { throw APIError(message: L.t("video_start_failed")) }
        return job.id
    }

    static func phase(from data: Data) throws -> VideoJobPhase {
        try VideoJobPhase(job: JSONDecoder().decode(Job.self, from: data))
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
        let (data, response) = try await HTTP.data(contentRequest(baseURL: baseURL, key: key, id: id))
        try HTTP.ensureAPISuccess(response, data: data)
        guard !(await URLSafety.isLocalOrPrivateResolved(response.url)) else {
            throw APIError(message: L.t("video_download_failed"))
        }
        return try VideoBytes.validated(data)
    }

    static func generate(baseURL: String, key: String, model: String,
                         request: VideoRequest, sourceVideo: Data?) async throws -> GeneratedVideo {
        let create = try createRequest(baseURL: baseURL, key: key, model: model,
                                       request: request, sourceVideo: sourceVideo)
        let created = try await HTTP.jsonData(create)
        let jobID = try await Offload.run { try Self.jobID(from: created) }
        flowMark("VIDEO auftrag task=\(jobID) model=\(model)")
        var polls = 0
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: pollInterval)
            polls += 1
            guard polls <= maximumPolls else {
                throw APIError(message: L.t("video_timeout"))
            }
            let job = try await HTTP.jsonData(try jobRequest(baseURL: baseURL, key: key, id: jobID))
            let state = try await Offload.run { try Self.phase(from: job) }
            switch state {
            case .pending, .running:
                flowMark("VIDEO warten task=\(jobID) runde=\(polls)")
            case .succeeded:
                flowMark("VIDEO fertig task=\(jobID) runde=\(polls)")
                return GeneratedVideo(data: try await download(baseURL: baseURL, key: key, id: jobID))
            case .failed(let message):
                throw APIError(message: message)
            }
        }
    }
}
