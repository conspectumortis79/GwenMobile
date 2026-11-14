import GwenMobileKit
import Foundation

struct PlaceGroup: Codable, Hashable, Sendable {
    static let defaultHeadingKey = "place_head"

    var headingKey: String
    var places: [NearbyPlace]

    enum CodingKeys: String, CodingKey {
        case headingKey, places
    }

    static func single(_ places: [NearbyPlace], headingKey: String?) -> [PlaceGroup]? {
        places.isEmpty ? nil : [PlaceGroup(headingKey: headingKey ?? defaultHeadingKey, places: places)]
    }

    static func combined(_ earlier: [PlaceGroup]?, _ later: [PlaceGroup]?) -> [PlaceGroup]? {
        var groups = earlier ?? []
        for group in later ?? [] {
            guard let index = groups.firstIndex(where: { $0.headingKey == group.headingKey }) else {
                groups.append(group)
                continue
            }
            groups[index].places += group.places.filter { !groups[index].places.contains($0) }
        }
        return groups.isEmpty ? nil : groups
    }
}

extension PlaceGroup {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        headingKey = fields.metadata(String.self, .headingKey, fallback: Self.defaultHeadingKey)
        places = fields.content([NearbyPlace].self, .places, fallback: [])
    }
}
