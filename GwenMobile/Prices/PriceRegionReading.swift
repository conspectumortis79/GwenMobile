import GwenMobileKit
import CoreLocation

@MainActor
protocol CountryGeocoding {
    func country(at location: CLLocation) async throws -> String?
}

@MainActor
final class StubCountryGeocoder: CountryGeocoding {
    func country(at location: CLLocation) async throws -> String? { nil }
}

@MainActor
enum CountryGeocoderPort {
    nonisolated(unsafe) static var current: any CountryGeocoding = StubCountryGeocoder()
}

@MainActor
final class LivePriceRegionReading: ObservableObject {
    private let fixer: any LocationFixing
    private let geocoder: any CountryGeocoding

    init(fixer: any LocationFixing = LiveLocationFix(),
         geocoder: any CountryGeocoding = CountryGeocoderPort.current) {
        self.fixer = fixer
        self.geocoder = geocoder
    }

    func region(named country: String?, whenLocalWish nearby: Bool) async -> PriceRegion {
        if let named = PriceRegion.named(country) { return named }
        if nearby {
            let located = await locatedRegion()
            if located.isNarrowed { return located }
        }
        return PriceRegion.device()
    }

    private func locatedRegion() async -> PriceRegion {
        do {
            let place = try await fixer.fix()
            guard let code = try await geocoder.country(at: place) else {
                flowMarkPersonal("PREISREGION standort ohne ländercode")
                return .unknown
            }
            let region = PriceRegion.located(code)
            flowMarkPersonal("PREISREGION standort \(region.traceLine)")
            return region
        } catch {
            flowMarkPersonal("PREISREGION standort fehl geschlagen "
                             + "grund=\(TextLine.oneLine(error.localizedDescription, limit: 60))")
            return .unknown
        }
    }
}
