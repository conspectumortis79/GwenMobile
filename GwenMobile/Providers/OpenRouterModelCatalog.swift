import GwenMobileKit
import Foundation

struct OpenRouterModelEntry: Decodable, Equatable, Sendable {
    struct Reasoning: Decodable, Equatable, Sendable {
        var supportedEfforts: [String]?
        var effortsListed: Bool
        var mandatory: Bool

        enum CodingKeys: String, CodingKey {
            case supportedEfforts = "supported_efforts"
            case mandatory
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mandatory = try container.decodeIfPresent(Bool.self, forKey: .mandatory) ?? false
            effortsListed = container.contains(.supportedEfforts)
            supportedEfforts = effortsListed
                ? try container.decodeIfPresent([String].self, forKey: .supportedEfforts)
                : nil
        }
    }

    struct Architecture: Decodable, Equatable, Sendable {
        var inputModalities: [String]?

        enum CodingKeys: String, CodingKey {
            case inputModalities = "input_modalities"
        }
    }

    var id: String
    var reasoning: Reasoning?
    var architecture: Architecture?
}

struct OpenRouterModelList: ModelListPayload, Sendable {
    var data: [OpenRouterModelEntry]
}

struct OpenRouterModelCatalog: ModelCatalog {
    typealias List = OpenRouterModelList
    static let imageModality = "image"
    static let videoModality = "video"

    static func id(of entry: OpenRouterModelEntry) -> String { entry.id }

    static func capabilities(of entry: OpenRouterModelEntry) -> ModelCapabilities {
        ModelCapabilities(thinking: thinking(of: entry.reasoning), vision: vision(of: entry.architecture),
                          video: video(of: entry.architecture))
    }

    static func thinking(of reasoning: OpenRouterModelEntry.Reasoning?) -> ThinkingCapabilities {
        guard let reasoning else { return ThinkingCapabilities(encoding: .openRouter, probed: true) }
        var levels: [ThinkingLevel] = []
        if reasoning.effortsListed {
            levels = reasoning.supportedEfforts.map { $0.compactMap(ThinkingLevel.init(rawValue:)) }
                ?? ThinkingCapabilities.gatewayLevels
        }
        if reasoning.mandatory { levels.removeAll { $0 == .off } }
        return ThinkingCapabilities(levels: levels.filter { $0 != .modelDefault },
                                    canSwitchOff: !reasoning.mandatory,
                                    encoding: .openRouter, probed: true)
    }

    static func vision(of architecture: OpenRouterModelEntry.Architecture?) -> VisionSupport {
        architecture?.inputModalities?.contains(imageModality) == true ? .supported : .rejected
    }

    static func video(of architecture: OpenRouterModelEntry.Architecture?) -> VisionSupport {
        guard let modalities = architecture?.inputModalities else { return .unknown }
        return modalities.contains(videoModality) ? .supported : .rejected
    }
}
