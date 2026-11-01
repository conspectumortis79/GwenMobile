import GwenMobileKit
import Foundation

enum ModelFilter {
    static let textExcludedMarkers = ["audio", "tts", "wan", "embed"]
    static let imageMarkers = ["wan", "image"]
    static let videoGenerationMarkers = ["t2v", "i2v", "video"]

    static func textCandidates(_ models: [String]) -> [String] {
        models.filter { !containsAny($0, textExcludedMarkers) }
    }

    static func imageCandidates(_ models: [String]) -> [String] {
        models.filter { containsAny($0, imageMarkers) && !containsAny($0, videoGenerationMarkers) }
    }

    static func visionCandidates(_ models: [String],
                                 caps: [String: ModelCapabilities]) -> [String] {
        let text = textCandidates(models)
        guard text.contains(where: { caps[$0]?.vision.isKnown ?? false }) else { return text }
        return text.filter { caps[$0]?.vision == .supported }
    }

    static func videoCandidates(_ models: [String],
                                caps: [String: ModelCapabilities]) -> [String] {
        let text = textCandidates(models)
        guard text.contains(where: { caps[$0]?.video.isKnown ?? false }) else { return [] }
        return text.filter { caps[$0]?.video == .supported }
    }

    static func videoGenerationCandidates(_ models: [String]) -> [String] {
        models.filter {
            containsAny($0, videoGenerationMarkers)
                && !containsAny($0, ["image", "2.7"])
        }
    }

    private static func containsAny(_ model: String, _ markers: [String]) -> Bool {
        markers.contains { model.contains($0) }
    }
}
