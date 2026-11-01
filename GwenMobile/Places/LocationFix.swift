import GwenMobileKit
import CoreLocation

@MainActor
protocol LocationFixing {
    func fix() async throws -> CLLocation
}

@MainActor
protocol LocationRequesting: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    #if DEBUG
    var accuracyAuthorization: CLAccuracyAuthorization { get }
    #endif
    var delegate: CLLocationManagerDelegate? { get set }
    func requestWhenInUseAuthorization()
    func requestLocation()
}

extension CLLocationManager: LocationRequesting {}

@MainActor
final class LiveLocationFix: NSObject, CLLocationManagerDelegate, LocationFixing {
    static let defaultTimeout: Duration = .seconds(20)

    private struct Waiter {
        let token: UUID
        let continuation: CheckedContinuation<CLLocation, Error>
    }

    private let manager: any LocationRequesting
    private let timeout: Duration
    private var waiter: Waiter?
    private var deadline: Task<Void, Never>?

    init(manager: any LocationRequesting = CLLocationManager(),
         timeout: Duration = LiveLocationFix.defaultTimeout) {
        self.manager = manager
        self.timeout = timeout
        super.init()
        manager.delegate = self
    }

    #if DEBUG
    var accessState: String {
        "\(manager.authorizationStatus.rawValue)/\(manager.accuracyAuthorization.rawValue)"
    }
    #endif

    func fix() async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .denied, .restricted: throw APIError(message: L.t("place_denied"))
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: break
        }
        return try await withCheckedThrowingContinuation { continuation in
            park(continuation)
        }
    }

    private func park(_ continuation: CheckedContinuation<CLLocation, Error>) {
        guard waiter == nil else {
            continuation.resume(throwing: APIError(message: L.t("place_busy")))
            return
        }
        let token = UUID()
        let lost = APIError(message: L.t("place_unavailable"))
        waiter = Waiter(token: token, continuation: continuation)
        if manager.authorizationStatus != .notDetermined {
            manager.requestLocation()
        }
        deadline = Task { @MainActor [weak self, timeout, lost] in
            try? await Task.sleep(for: timeout)
            guard let self else { return }
            self.settle(token, .failure(lost))
        }
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if waiter != nil { manager.requestLocation() }
        case .denied, .restricted:
            refuse(APIError(message: L.t("place_denied")))
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationChanged(self.manager.authorizationStatus)
        }
    }

    private func settle(_ token: UUID, _ result: Result<CLLocation, Error>) {
        guard let waiter, waiter.token == token else { return }
        self.waiter = nil
        deadline?.cancel()
        deadline = nil
        waiter.continuation.resume(with: result)
    }

    private func deliver(_ fix: CLLocation?) {
        let outcome: Result<CLLocation, Error> = fix.map { .success($0) }
            ?? .failure(APIError(message: L.t("place_unavailable")))
        settleCurrent(outcome)
    }

    private func refuse(_ reason: APIError) {
        settleCurrent(.failure(reason))
    }

    private func settleCurrent(_ result: Result<CLLocation, Error>) {
        guard let token = waiter?.token else { return }
        settle(token, result)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fix = locations.last
        Task { @MainActor in
            self.deliver(fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as NSError).code == CLError.denied.rawValue
        let reason = APIError(message: denied ? L.t("place_denied") : error.localizedDescription)
        Task { @MainActor in
            self.refuse(reason)
        }
    }
}
