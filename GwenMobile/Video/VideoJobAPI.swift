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

enum VideoJobPolling {
    enum Step<Result: Sendable>: Sendable {
        case waiting
        case finished(Result)
        case failed(String)
    }

    static func run<Result: Sendable>(
        taskID: String,
        model: String,
        interval: Duration,
        maximumPolls: Int,
        check: () async throws -> Step<Result>
    ) async throws -> Result {
        flowMark("VIDEO auftrag task=\(taskID) model=\(model)")
        var polls = 0
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: interval)
            polls += 1
            guard polls <= maximumPolls else {
                throw APIError(message: L.t("video_timeout"))
            }
            switch try await check() {
            case .waiting:
                flowMark("VIDEO warten task=\(taskID) runde=\(polls)")
            case .finished(let result):
                flowMark("VIDEO fertig task=\(taskID) runde=\(polls)")
                return result
            case .failed(let message):
                throw APIError(message: message)
            }
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

extension VideoJobAPIKind {
    static var videosPath: String { "/videos" }
    private static var modelsPath: String { "/videos/models" }
    private static var maximumPolls: Int { 60 }

    static func fetchModelIDs(baseURL: String, key: String) async throws -> [String] {
        try await IDModelList.fetchIDs(baseURL: baseURL, path: modelsPath, key: key)
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
        let segment = try HTTP.pathSegment(id)
        return try HTTP.authorizedGET(baseURL: baseURL, path: videosPath + "/" + segment, key: key,
                                      timeout: APITimeout.videoRequest)
    }

    static func contentRequest(baseURL: String, key: String, id: String) throws -> URLRequest {
        let segment = try HTTP.pathSegment(id)
        return try HTTP.authorizedGET(baseURL: baseURL, path: videosPath + "/" + segment + "/content", key: key,
                                      timeout: APITimeout.videoDownload)
    }

    static func download(baseURL: String, key: String, id: String) async throws -> Data {
        let local = await URLSafety.isLocalOrPrivateResolved(URL(string: baseURL))
        let (data, response) = try await HTTP.data(contentRequest(baseURL: baseURL, key: key, id: id),
                                                   allowLocalRedirects: local)
        try HTTP.ensureAPISuccess(response, data: data)
        if !local {
            try await HTTP.ensurePublicOrigin(response, refusal: L.t("video_download_failed"))
        }
        return try VideoBytes.validated(data)
    }

    static func generate(baseURL: String, key: String, model: String,
                         request: VideoRequest, sourceVideo: Data?) async throws -> GeneratedVideo {
        let create = try createRequest(baseURL: baseURL, key: key, model: model,
                                       request: request, sourceVideo: sourceVideo)
        let created = try await HTTP.jsonData(create)
        let jobID = try await Offload.run { try Self.jobID(from: created) }
        try await VideoJobPolling.run(taskID: jobID, model: model, interval: pollInterval,
                                      maximumPolls: maximumPolls) { () async throws -> VideoJobPolling.Step<Void> in
            let job = try await HTTP.jsonData(try jobRequest(baseURL: baseURL, key: key, id: jobID))
            switch try await Offload.run({ try Self.phase(from: job) }) {
            case .pending, .running: return .waiting
            case .succeeded: return .finished(())
            case .failed(let message): return .failed(message)
            }
        }
        return GeneratedVideo(data: try await download(baseURL: baseURL, key: key, id: jobID))
    }
}
