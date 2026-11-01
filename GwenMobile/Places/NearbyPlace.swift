import GwenMobileKit
import Foundation

struct NearbyPlace: Codable, Hashable, Sendable {
    var name: String
    var latitude: Double?
    var longitude: Double?
    var metres: Int?
    var mode: TravelMode = .walking

    var distanceText: String? {
        guard let metres else { return nil }
        return metres < 950 ? L.n("place_metres", metres)
                            : L.n("place_kilometres", Int((Double(metres) / 1000).rounded()))
    }

    var coordinateKey: String? {
        guard let latitude, let longitude else { return nil }
        return String(format: "%.4f,%.4f", latitude, longitude)
    }

    var directionsURL: URL? {
        guard let latitude, let longitude else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        var items = [URLQueryItem(name: "daddr", value: String(format: "%.6f,%.6f", latitude, longitude)),
                     URLQueryItem(name: "q", value: name)]
        if let flag = mode.mapsURLFlag { items.append(URLQueryItem(name: "dirflg", value: flag)) }
        components?.queryItems = items
        return components?.url
    }

    enum CodingKeys: String, CodingKey {
        case name, latitude, longitude, metres, mode
    }
}

extension NearbyPlace {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        name = fields.content(String.self, .name, fallback: "")
        latitude = fields.content(Double.self, .latitude)
        longitude = fields.content(Double.self, .longitude)
        metres = fields.metadata(Int.self, .metres)
        mode = fields.metadata(TravelMode.self, .mode, fallback: .walking)
    }
}
