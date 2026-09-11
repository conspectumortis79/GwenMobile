import Foundation

struct ModelCapabilities: Codable, Equatable, Sendable {
    var thinking = ThinkingCapabilities.unknown
    var vision: VisionSupport = .unknown

    var isComplete: Bool { thinking.isKnown && vision.isKnown }
}

protocol ModelDiscovering: Sendable {
    func discover(baseURL: String, key: String, models: [String]) async -> [String: ModelCapabilities]
}

struct QwenModelProber: ModelDiscovering {
    func discover(baseURL: String, key: String, models: [String]) async -> [String: ModelCapabilities] {
        let probed = await ModelProbeRunner.run(models) { model in
            async let thinking = ThinkingCapabilityProbe.capabilities(baseURL: baseURL, key: key, model: model)
            async let vision = VisionCapabilityProbe.support(baseURL: baseURL, key: key, model: model)
            return ModelCapabilities(thinking: await thinking, vision: await vision)
        }
        return probed.filter { $0.value.isComplete }
    }
}

enum ModelProbeRunner {
    static let parallelModels = 4

    static func run<Outcome: Sendable>(_ models: [String],
                                       limit: Int = parallelModels,
                                       probe: @escaping @Sendable (String) async -> Outcome) async -> [String: Outcome] {
        var collected: [String: Outcome] = [:]
        let width = max(1, limit)
        for start in stride(from: 0, to: models.count, by: width) {
            let slice = Array(models[start..<min(start + width, models.count)])
            let round = await withTaskGroup(of: (String, Outcome).self) { group in
                for model in slice {
                    group.addTask { (model, await probe(model)) }
                }
                var results: [String: Outcome] = [:]
                for await (model, outcome) in group {
                    results[model] = outcome
                }
                return results
            }
            collected.merge(round) { _, new in new }
        }
        return collected
    }
}
