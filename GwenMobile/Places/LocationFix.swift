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

    private struct Round {
        let token: UUID
        var waiting: [CheckedContinuation<CLLocation, Error>]
    }

    private let manager: any LocationRequesting
    private let timeout: Duration
    private var round: Round?
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
        guard round == nil else {
            round?.waiting.append(continuation)
            return
        }
        let token = UUID()
        let lost = APIError(message: L.t("place_unavailable"))
        round = Round(token: token, waiting: [continuation])
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
            if round != nil { manager.requestLocation() }
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
        guard let round, round.token == token else { return }
        self.round = nil
        deadline?.cancel()
        deadline = nil
        for continuation in round.waiting { continuation.resume(with: result) }
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
        guard let token = round?.token else { return }
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
        let reason = APIError(message: L.t(denied ? "place_denied" : "place_unavailable"))
        flowMarkPersonal("ORT standort fehler=\(error.localizedDescription)")
        Task { @MainActor in
            self.refuse(reason)
        }
    }
}
