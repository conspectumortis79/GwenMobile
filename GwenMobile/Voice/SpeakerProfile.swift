import Foundation
import Security

enum SpeakerSensitivity: Int, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case strict
    case normal
    case relaxed

    var id: Int { rawValue }

    var key: String {
        switch self {
        case .strict: return "speaker_sensitivity_strict"
        case .normal: return "speaker_sensitivity_normal"
        case .relaxed: return "speaker_sensitivity_relaxed"
        }
    }
}

enum SpeakerVerdict: Equatable, Sendable {
    case unknown
    case allowed
    case rejected
}

struct SpeakerProfile: Codable, Equatable, Sendable {
    static let currentModel = "wespeaker-resnet34-lm-coreml-2s-v1"
    static let dimension = 256

    var model: String
    var embeddings: [[Float]]
    var threshold: Float

    var sampleCount: Int { embeddings.count }

    var isValid: Bool {
        model == Self.currentModel && !embeddings.isEmpty
            && embeddings.allSatisfy { $0.count == Self.dimension }
    }

    func threshold(for sensitivity: SpeakerSensitivity) -> Float {
        switch sensitivity {
        case .strict: return min(0.85, threshold + 0.08)
        case .normal: return threshold
        case .relaxed: return max(0.35, threshold - 0.08)
        }
    }

    func bestScore(for embedding: [Float]) -> Float {
        guard embedding.count == Self.dimension else { return -1 }
        return embeddings.reduce(-1) { best, known in
            max(best, SpeakerProfileBuilder.cosine(known, embedding))
        }
    }
}

protocol SpeakerProfileStoring: Sendable {
    func load() -> SpeakerProfile?
    @discardableResult func save(_ profile: SpeakerProfile) -> Bool
    @discardableResult func delete() -> Bool
}

struct SpeakerProfileStore: SpeakerProfileStoring {
    static let shared = SpeakerProfileStore()

    private let item: KeychainItem

    init(service: String = "GwenMobile", account: String = "speakerProfile") {
        item = KeychainItem(service: service, account: account, scope: .thisDevice)
    }

    func load() -> SpeakerProfile? {
        let (status, found) = item.read(withAttributes: false)
        guard status == errSecSuccess, let data = found as? Data,
              let profile = try? JSONDecoder().decode(SpeakerProfile.self, from: data),
              profile.isValid else { return nil }
        return profile
    }

    @discardableResult
    func save(_ profile: SpeakerProfile) -> Bool {
        guard profile.isValid, let data = try? JSONEncoder().encode(profile) else { return false }
        return item.write(data) == .done
    }

    @discardableResult
    func delete() -> Bool {
        item.delete() == .done
    }
}

enum SpeakerAudioWindows {
    static let sampleRate = 16000
    static let windowSamples = 32000
    static let hopSamples = 16000
    static let minimumRMS: Float = 0.006
    static let targetPeak: Float = 0.25

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return Float((sum / Double(samples.count)).squareRoot())
    }

    static func normalized(_ samples: [Float]) -> [Float]? {
        guard samples.count == windowSamples else { return nil }
        let peak = samples.reduce(0.0) { max($0, abs($1)) }
        guard peak > 0.001 else { return nil }
        let gain = min(4.0, targetPeak / peak)
        return samples.map { $0 * gain }
    }

    static func windows(from samples: [Float], minimumSamples: Int = sampleRate) -> [[Float]] {
        guard samples.count >= max(1, minimumSamples), !samples.isEmpty else { return [] }
        let starts: [Int]
        if samples.count >= windowSamples {
            var found: [Int] = []
            var start = 0
            while start + windowSamples <= samples.count {
                found.append(start)
                start += hopSamples
            }
            let last = samples.count - windowSamples
            if found.last != last { found.append(last) }
            starts = found
        } else {
            starts = [0]
        }
        return starts.compactMap { start in
            var window: [Float]
            if start + windowSamples <= samples.count {
                window = Array(samples[start..<start + windowSamples])
            } else {
                window = Array(samples[start...])
                guard !window.isEmpty else { return nil }
                while window.count < windowSamples {
                    window.append(contentsOf: window.prefix(windowSamples - window.count))
                }
                window = Array(window.prefix(windowSamples))
            }
            guard rms(window) >= minimumRMS else { return nil }
            return normalized(window)
        }
    }
}

enum SpeakerScorePolicy {
    static func early(_ scores: [Float], threshold: Float) -> SpeakerVerdict {
        guard let last = scores.last else { return .unknown }
        if last >= threshold + 0.03 { return .allowed }
        if scores.count >= 2, last < threshold - 0.08 { return .rejected }
        return .unknown
    }

    static func final(_ scores: [Float], threshold: Float) -> SpeakerVerdict {
        guard let best = scores.max() else { return .rejected }
        return best >= threshold ? .allowed : .rejected
    }
}

enum SpeakerProfileBuilder {
    static let maximumEmbeddings = 16

    static func cosine(_ left: [Float], _ right: [Float]) -> Float {
        guard left.count == right.count, !left.isEmpty else { return -1 }
        var sum: Float = 0
        for index in left.indices {
            sum += left[index] * right[index]
        }
        return sum
    }

    static func normalized(_ embedding: [Float]) -> [Float]? {
        guard embedding.count == SpeakerProfile.dimension else { return nil }
        let norm = embedding.reduce(0.0) { $0 + Double($1) * Double($1) }.squareRoot()
        guard norm > 1.0e-9 else { return nil }
        return embedding.map { Float(Double($0) / norm) }
    }

    static func profile(from embeddings: [[Float]], threshold: Float = 0.55) -> SpeakerProfile? {
        let valid = embeddings.compactMap(normalized)
        guard !valid.isEmpty else { return nil }
        return SpeakerProfile(model: SpeakerProfile.currentModel,
                              embeddings: Array(valid.prefix(maximumEmbeddings)),
                              threshold: threshold)
    }

    static func consistency(of embeddings: [[Float]]) -> Float? {
        guard embeddings.count >= 2 else { return nil }
        var lowest: Float = 1
        for index in embeddings.indices {
            var best: Float = -1
            for other in embeddings.indices where other != index {
                best = max(best, cosine(embeddings[index], embeddings[other]))
            }
            lowest = min(lowest, best)
        }
        return lowest
    }
}
