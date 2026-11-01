import GwenMobileKit
import Foundation

enum QwenVideoAPI {
    static let synthesisPath = "/services/aigc/video-generation/video-synthesis"
    static let tasksPath = "/tasks/"
    nonisolated(unsafe) static var pollInterval = Duration.seconds(15)
    static let maximumPolls = 40

    struct TaskState: Equatable, Sendable {
        enum Phase: Equatable, Sendable {
            case pending
            case running
            case succeeded(URL)
            case failed(String)
        }

        var phase: Phase
    }

    static func base(fromChatBase baseURL: String) throws -> String {
        let root = HTTP.root(baseURL)
        let suffix = "/compatible-mode/v1"
        guard root.hasSuffix(suffix), root.count > suffix.count else {
            throw APIError(message: L.t("bad_url"))
        }
        return String(root.dropLast(suffix.count)) + "/api/v1"
    }

    static func createRequest(baseURL: String, key: String, model: String,
                              request: VideoRequest,
                              sourceURL: String? = nil) throws -> URLRequest {
        let base = try base(fromChatBase: baseURL)
        let url = try HTTP.requiredURL(base, synthesisPath)
        var prepared = try HTTP.jsonPOST(url: url, key: key,
                                         body: body(model: model, request: request, sourceURL: sourceURL),
                                         timeout: APITimeout.videoRequest)
        prepared.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")
        return prepared
    }

    static func body(model: String, request: VideoRequest, sourceURL: String? = nil) -> [String: Any] {
        var input: [String: Any] = ["prompt": request.prompt]
        if let sourceURL {
            input["media"] = [["type": "reference_video", "url": sourceURL]]
        }
        var parameters: [String: Any] = [
            "duration": request.clampedDuration,
            "prompt_extend": sourceURL == nil,
        ]
        if sourceURL != nil {
            parameters["resolution"] = "720P"
        } else if usesStructuredParameters(model) {
            parameters["resolution"] = "720P"
            parameters["ratio"] = request.ratio.rawValue
        } else {
            parameters["size"] = request.ratio.size
        }
        return [
            "model": model,
            "input": input,
            "parameters": parameters,
        ]
    }

    static func usesStructuredParameters(_ model: String) -> Bool {
        guard let version = wanVersion(model) else { return true }
        return version >= 2.7
    }

    static func wanVersion(_ model: String) -> Double? {
        let lower = model.lowercased()
        guard let start = lower.range(of: "wan") else { return nil }
        let number = lower[start.upperBound...].prefix { $0.isNumber || $0 == "." }
        return number.isEmpty ? nil : Double(number)
    }

    static func taskRequest(baseURL: String, key: String, taskID: String) throws -> URLRequest {
        let base = try base(fromChatBase: baseURL)
        let url = try HTTP.requiredURL(base, tasksPath + taskID)
        return HTTP.authorizedGET(url: url, key: key, timeout: APITimeout.videoRequest)
    }

    static func taskID(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(CreateResponse.self, from: data)
        guard !response.output.taskID.isEmpty else {
            throw APIError(message: L.t("video_start_failed"))
        }
        return response.output.taskID
    }

    static func state(from data: Data) throws -> TaskState {
        let response = try JSONDecoder().decode(TaskResponse.self, from: data)
        switch response.output.taskStatus.uppercased() {
        case "PENDING":
            return TaskState(phase: .pending)
        case "RUNNING":
            return TaskState(phase: .running)
        case "SUCCEEDED":
            guard let raw = response.output.videoURL, let url = URL(string: raw),
                  url.scheme == "https" else {
                throw APIError(message: L.t("video_download_failed"))
            }
            return TaskState(phase: .succeeded(url))
        case "FAILED":
            return TaskState(phase: .failed(failureText(response.output)))
        default:
            throw APIError(message: L.t("video_timeout"))
        }
    }

    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = APITimeout.videoDownload
        let (data, response) = try await HTTP.data(request)
        try HTTP.ensureSuccess(response)
        guard data.count <= VideoPolicy.maxBytes, VideoBytes.isVideo(data) else {
            throw APIError(message: L.t("video_download_failed"))
        }
        return data
    }

    private static func failureText(_ output: TaskResponse.Output) -> String {
        let detail = [output.code, output.message]
            .compactMap { $0?.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: ": ")
        return detail.isEmpty ? L.t("video_generation_failed") : detail
    }

    private struct CreateResponse: Decodable {
        struct Output: Decodable {
            var taskID: String

            enum CodingKeys: String, CodingKey {
                case taskID = "task_id"
            }
        }

        var output: Output
    }

    private struct TaskResponse: Decodable {
        struct Output: Decodable {
            var taskStatus: String
            var videoURL: String?
            var code: String?
            var message: String?

            enum CodingKeys: String, CodingKey {
                case taskStatus = "task_status"
                case videoURL = "video_url"
                case code, message
            }
        }

        var output: Output
    }
}

struct QwenVideoBackend: VideoGenerating {
    func generate(baseURL: String, key: String, model: String,
                  request: VideoRequest, sourceVideo: Data?) async throws -> GeneratedVideo {
        let sourceURL = sourceVideo.map {
            "data:\(VideoBytes.mimeType($0));base64,\($0.base64EncodedString())"
        }
        if let sourceVideo {
            flowMark("VIDEO quelle bytes=\(sourceVideo.count)")
        }
        let create = try QwenVideoAPI.createRequest(baseURL: baseURL, key: key, model: model,
                                                    request: request, sourceURL: sourceURL)
        let created = try await HTTP.jsonData(create)
        let taskID = try await Offload.run { try QwenVideoAPI.taskID(from: created) }
        flowMark("VIDEO auftrag task=\(taskID) model=\(model)")
        var polls = 0
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: QwenVideoAPI.pollInterval)
            polls += 1
            guard polls <= QwenVideoAPI.maximumPolls else {
                throw APIError(message: L.t("video_timeout"))
            }
            let task = try await HTTP.jsonData(try QwenVideoAPI.taskRequest(baseURL: baseURL, key: key,
                                                                             taskID: taskID))
            let state = try await Offload.run { try QwenVideoAPI.state(from: task) }
            switch state.phase {
            case .pending, .running:
                flowMark("VIDEO warten task=\(taskID) runde=\(polls)")
            case .succeeded(let url):
                flowMark("VIDEO fertig task=\(taskID) runde=\(polls)")
                let data = try await QwenVideoAPI.download(url)
                return GeneratedVideo(data: data)
            case .failed(let message):
                throw APIError(message: message)
            }
        }
    }
}
