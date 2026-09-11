import Foundation

enum ModelFilter {
    static let textExcludedMarkers = ["audio", "tts", "wan"]
    static let imageMarkers = ["wan", "image"]

    static func textCandidates(_ models: [String]) -> [String] {
        models.filter { !containsAny($0, textExcludedMarkers) }
    }

    static func imageCandidates(_ models: [String]) -> [String] {
        models.filter { containsAny($0, imageMarkers) }
    }

    static func audioCandidates(_ models: [String]) -> [String] {
        models.filter { $0.contains("asr") || ($0.contains("audio") && !$0.contains("tts")) }
    }

    private static func containsAny(_ model: String, _ markers: [String]) -> Bool {
        markers.contains { model.contains($0) }
    }
}
