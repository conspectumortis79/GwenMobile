import GwenMobileKit
import Foundation

enum VideoRatio: String, CaseIterable, Sendable {
    case landscape = "16:9"
    case portrait = "9:16"
    case square = "1:1"
    case fourThree = "4:3"
    case threeFour = "3:4"

    var size: String {
        switch self {
        case .landscape: return "1280*720"
        case .portrait: return "720*1280"
        case .square: return "960*960"
        case .fourThree: return "1088*832"
        case .threeFour: return "832*1088"
        }
    }
}

struct VideoRequest: Equatable, Sendable {
    static let defaultDuration = 5
    static let minimumDuration = 2
    static let maximumDuration = 15

    var prompt: String
    var duration: Int
    var ratio: VideoRatio

    init(prompt: String, duration: Int = VideoRequest.defaultDuration,
         ratio: VideoRatio = .landscape) {
        self.prompt = prompt
        self.duration = duration
        self.ratio = ratio
    }

    var clampedDuration: Int {
        min(max(duration, Self.minimumDuration), Self.maximumDuration)
    }

    var stepWords: String {
        "\(prompt) \(clampedDuration)s \(ratio.rawValue)"
    }

    static func from(_ args: [String: Any]) -> VideoRequest? {
        guard let raw = (args["prompt"] as? String)?.trimmed, !raw.isEmpty else { return nil }
        let duration = args["duration"] as? Int ?? defaultDuration
        let ratio = (args["ratio"] as? String).flatMap(VideoRatio.init(rawValue:)) ?? .landscape
        return VideoRequest(prompt: raw, duration: duration, ratio: ratio)
    }
}

struct GeneratedVideo: Equatable, Sendable {
    var data: Data
    var fileExtension: String = "mp4"
}

protocol VideoGenerating: Sendable {
    func generate(baseURL: String, key: String, model: String,
                  request: VideoRequest, sourceVideo: Data?) async throws -> GeneratedVideo
}

extension VideoGenerating {
    func generate(baseURL: String, key: String, model: String,
                  request: VideoRequest) async throws -> GeneratedVideo {
        try await generate(baseURL: baseURL, key: key, model: model, request: request, sourceVideo: nil)
    }
}

enum VideoPolicy {
    static let maxBytes = 200_000_000
    static let maximumAttachmentBytes = FilePolicy.maxFileBytes
}

enum VideoBytes {
    static func isVideo(_ data: Data) -> Bool {
        guard data.count > 12 else { return false }
        if data[4..<8].elementsEqual("ftyp".utf8) { return true }
        return data[0..<4].elementsEqual([0x1A, 0x45, 0xDF, 0xA3])
    }

    static func mimeType(_ data: Data) -> String {
        guard data.count > 12 else { return "video/mp4" }
        if data[4..<12].elementsEqual("ftypqt  ".utf8) { return "video/quicktime" }
        return "video/mp4"
    }
}
