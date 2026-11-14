import GwenMobileKit
import Foundation

struct DeepSeekModelEntry: Decodable, Equatable, Sendable {
    struct Effort: Decodable, Equatable, Sendable {
        var supportedLevels: [String]

        enum CodingKeys: String, CodingKey {
            case supportedLevels = "supported_levels"
        }

        init(supportedLevels: [String]) {
            self.supportedLevels = supportedLevels
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            supportedLevels = try container.decodeIfPresent([String].self, forKey: .supportedLevels) ?? []
        }
    }

    var id: String
    var inputModalities: [String]?
    var effort: Effort?

    enum CodingKeys: String, CodingKey {
        case id
        case inputModalities = "input_modalities"
        case effort
        case supportedLevels = "supported_levels"
        case defaultLevel = "default_level"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        inputModalities = try container.decodeIfPresent([String].self, forKey: .inputModalities)
        if let nested = try container.decodeIfPresent(Effort.self, forKey: .effort) {
            effort = nested
        } else if container.contains(.supportedLevels) || container.contains(.defaultLevel) {
            effort = Effort(supportedLevels: try container.decodeIfPresent([String].self,
                                                                          forKey: .supportedLevels) ?? [])
        } else {
            effort = nil
        }
    }
}

struct DeepSeekModelList: ModelListPayload, Sendable {
    var data: [DeepSeekModelEntry]
}

struct DeepSeekModelCatalog: ModelCatalog {
    typealias List = DeepSeekModelList
    static let imageModality = "image"

    static func id(of entry: DeepSeekModelEntry) -> String { entry.id }

    static func capabilities(of entry: DeepSeekModelEntry) -> ModelCapabilities {
        ModelCapabilities(thinking: thinking(of: entry.effort), vision: vision(of: entry))
    }

    static func thinking(of effort: DeepSeekModelEntry.Effort?) -> ThinkingCapabilities {
        guard let effort else { return ThinkingCapabilities(encoding: .openAI, probed: true) }
        let levels = effort.supportedLevels.compactMap(ThinkingLevel.init(rawValue:))
            .filter { $0 != .modelDefault }
        return ThinkingCapabilities(levels: levels, canSwitchOff: true, encoding: .openAI, probed: true)
    }

    static func vision(of entry: DeepSeekModelEntry) -> VisionSupport {
        guard let modalities = entry.inputModalities else { return .unknown }
        return modalities.contains(imageModality) ? .supported : .rejected
    }
}
