@testable import GwenMobileFeatureCore
import GwenMobileKit
import CoreLocation
import Foundation
import MapKit

@MainActor
final class LiveCountryGeocoder: CountryGeocoding {
    static let timeout: Duration = .seconds(15)

    func country(at location: CLLocation) async throws -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let deadline = Task { @MainActor in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled else { return }
            request.cancel()
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            let items = try await request.mapItems
            return items.first?.addressRepresentations?.region?.identifier
        } onCancel: {
            request.cancel()
        }
    }
}

@MainActor
enum PriceRegionSystem {
    static func install() {
        CountryGeocoderPort.current = LiveCountryGeocoder()
    }
}
