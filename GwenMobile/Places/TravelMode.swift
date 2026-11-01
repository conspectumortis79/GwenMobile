import GwenMobileKit
import MapKit

enum TravelMode: String, Codable, Sendable, CaseIterable {
    case walking
    case driving
    case transit
    case cycling
    case automatic

    var labelKey: String {
        switch self {
        case .walking: return "mode_walking"
        case .driving: return "mode_driving"
        case .transit: return "mode_transit"
        case .cycling: return "mode_cycling"
        case .automatic: return "mode_automatic"
        }
    }

    var label: String { L.t(labelKey) }

    var launchOption: String {
        switch self {
        case .walking: return MKLaunchOptionsDirectionsModeWalking
        case .driving: return MKLaunchOptionsDirectionsModeDriving
        case .transit: return MKLaunchOptionsDirectionsModeTransit
        case .cycling: return MKLaunchOptionsDirectionsModeCycling
        case .automatic: return MKLaunchOptionsDirectionsModeDefault
        }
    }

    var mapsURLFlag: String? {
        switch self {
        case .driving: return "d"
        case .walking: return "w"
        case .transit, .cycling, .automatic: return nil
        }
    }
}
