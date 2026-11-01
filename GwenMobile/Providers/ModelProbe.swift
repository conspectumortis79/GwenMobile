import GwenMobileKit
import Foundation

struct ModelCapabilities: Codable, Equatable, Sendable {
    var thinking = ThinkingCapabilities.unknown
    var vision: VisionSupport = .unknown
    var video: VisionSupport = .unknown

    var isComplete: Bool { thinking.isKnown && vision.isKnown }

    func isCurrent(for encoding: ThinkingEncoding) -> Bool {
        isComplete && thinking.encoding == encoding
    }
}

protocol ModelDiscovering: Sendable {
    func discover(baseURL: String, key: String, models: [String]) async -> [String: ModelCapabilities]
}

protocol ModelListPayload: Decodable, Sendable {
    associatedtype Entry: Sendable
    var data: [Entry] { get }
}

enum ModelCatalogDiscovery {
    static func discover<List: ModelListPayload>(baseURL: String, key: String, models: [String],
                                                 list: List.Type,
                                                 id: (List.Entry) -> String,
                                                 capabilities: (List.Entry) -> ModelCapabilities)
        async -> [String: ModelCapabilities] {
        guard let request = try? QwenAPI.fetchModelsRequest(baseURL: baseURL, key: key),
              let data = try? await HTTP.jsonData(request),
              let payload = try? await Offload.run({ try JSONDecoder().decode(List.self, from: data) })
        else { return [:] }
        return Self.capabilities(of: payload.data, for: models, id: id, capabilities: capabilities)
    }

    static func capabilities<Entry>(of entries: [Entry], for models: [String],
                                    id: (Entry) -> String,
                                    capabilities: (Entry) -> ModelCapabilities) -> [String: ModelCapabilities] {
        let wanted = Set(models)
        var found: [String: ModelCapabilities] = [:]
        for entry in entries where wanted.contains(id(entry)) {
            found[id(entry)] = capabilities(entry)
        }
        return found
    }
}

protocol ModelCatalog: ModelDiscovering {
    associatedtype List: ModelListPayload

    static func id(of entry: List.Entry) -> String
    static func capabilities(of entry: List.Entry) -> ModelCapabilities
}

extension ModelCatalog {
    func discover(baseURL: String, key: String, models: [String]) async -> [String: ModelCapabilities] {
        await ModelCatalogDiscovery.discover(baseURL: baseURL, key: key, models: models,
                                             list: List.self,
                                             id: { Self.id(of: $0) },
                                             capabilities: { Self.capabilities(of: $0) })
    }

    #if DEBUG
    static func capabilities(of entries: [List.Entry], for models: [String]) -> [String: ModelCapabilities] {
        ModelCatalogDiscovery.capabilities(of: entries, for: models,
                                           id: { Self.id(of: $0) },
                                           capabilities: { Self.capabilities(of: $0) })
    }
    #endif
}

struct CapabilityProber: ModelDiscovering {
    let requiresImageTokens: Bool
    let videoFromVision: Bool
    let thinking: @Sendable (String, String, String) async -> ThinkingCapabilities

    init(requiresImageTokens: Bool, videoFromVision: Bool = false,
         thinking: @escaping @Sendable (String, String, String) async -> ThinkingCapabilities) {
        self.requiresImageTokens = requiresImageTokens
        self.videoFromVision = videoFromVision
        self.thinking = thinking
    }

    func discover(baseURL: String, key: String, models: [String]) async -> [String: ModelCapabilities] {
        let prober = self
        let probed = await ModelProbeRunner.run(models) { model in
            async let thinking = prober.thinking(baseURL, key, model)
            async let vision = VisionCapabilityProbe.support(baseURL: baseURL, key: key, model: model,
                                                            requiresImageTokens: prober.requiresImageTokens)
            let seen = await vision
            return ModelCapabilities(thinking: await thinking, vision: seen,
                                     video: prober.videoFromVision ? seen : .unknown)
        }
        return probed.filter { $0.value.isComplete }
    }
}

extension CapabilityProber {
    static let dashScope = CapabilityProber(requiresImageTokens: true, videoFromVision: true) { baseURL, key, model in
        await ThinkingCapabilityProbe.capabilities(baseURL: baseURL, key: key, model: model)
    }

    static let openAI = CapabilityProber(requiresImageTokens: false) { baseURL, key, model in
        await OpenAIThinkingProbe.capabilities(baseURL: baseURL, key: key, model: model)
    }
}

enum ModelProbeRunner {
    static let parallelModels = 4

    static func run<Outcome: Sendable>(_ models: [String],
                                       probe: @escaping @Sendable (String) async -> Outcome) async -> [String: Outcome] {
        var collected: [String: Outcome] = [:]
        for start in stride(from: 0, to: models.count, by: parallelModels) {
            let slice = Array(models[start..<min(start + parallelModels, models.count)])
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
            for (key, value) in round { collected[key] = value }
        }
        return collected
    }
}
