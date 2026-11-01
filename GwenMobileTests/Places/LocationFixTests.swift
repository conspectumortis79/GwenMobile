@testable import GwenMobileFeatureCore
import CoreLocation
import XCTest
import GwenMobileKit

@MainActor
private final class FakeLocationManager: LocationRequesting {
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    weak var delegate: CLLocationManagerDelegate?

    private(set) var prompts = 0
    private(set) var requests = 0
    private let sender = CLLocationManager()

    func requestWhenInUseAuthorization() { prompts += 1 }

    func requestLocation() { requests += 1 }

    func changeAuthorization(to status: CLAuthorizationStatus) {
        authorizationStatus = status
        delegate?.locationManagerDidChangeAuthorization?(sender)
    }

    func deliver(_ locations: [CLLocation]) {
        delegate?.locationManager?(sender, didUpdateLocations: locations)
    }

    func refuse(_ error: Error) {
        delegate?.locationManager?(sender, didFailWithError: error)
    }
}

@MainActor
final class LocationFixTests: GwenTestCase {
    private enum Outcome: Equatable {
        case fixed(String)
        case refused(String)
        case stalled
    }

    private func outcome(of fix: LiveLocationFix, patience: Duration = .seconds(5)) async -> Outcome {
        let box = LockedValue<Outcome?>(nil)
        let request = Task { @MainActor in
            do {
                let position = try await fix.fix()
                box.set(.fixed(String(format: "%.4f,%.4f", position.coordinate.latitude,
                                      position.coordinate.longitude)))
            } catch let error as APIError {
                box.set(.refused(error.message))
            } catch {
                box.set(.refused(error.localizedDescription))
            }
        }
        let started = ContinuousClock.now
        while box.current == nil, started.duration(to: .now) < patience {
            try? await Task.sleep(for: .milliseconds(20))
        }
        request.cancel()
        return box.current ?? .stalled
    }

    private func fixer(_ manager: FakeLocationManager, after: Duration = .milliseconds(120)) -> LiveLocationFix {
        LiveLocationFix(manager: manager, timeout: after)
    }

    private func handBack(_ manager: FakeLocationManager, _ positions: [CLLocation], after: Duration) -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: after)
            manager.deliver(positions)
        }
    }

    func testARequestThatNeverAnswersEndsInAnUnavailableAnswerInsteadOfAnEndlessWait() async {
        let manager = FakeLocationManager()
        let result = await outcome(of: fixer(manager))
        XCTAssertEqual(result, .refused(L.t("place_unavailable")))
        XCTAssertEqual(manager.requests, 1)
    }

    func testATimedOutRequestFreesTheSlotForTheNextOne() async {
        let manager = FakeLocationManager()
        let fix = fixer(manager)
        let first = await outcome(of: fix)
        XCTAssertEqual(first, .refused(L.t("place_unavailable")))
        let delivery = handBack(manager, [CLLocation(latitude: 52.5163, longitude: 13.3777)],
                                after: .milliseconds(40))
        let second = await outcome(of: fix)
        XCTAssertEqual(second, .fixed("52.5163,13.3777"))
        await delivery.value
    }

    func testADeniedPermissionRefusesBeforeAskingTheManagerForAPlace() async {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .denied
        let result = await outcome(of: fixer(manager))
        XCTAssertEqual(result, .refused(L.t("place_denied")))
        XCTAssertEqual(manager.requests, 0)
    }

    func testAStillUnknownPermissionIsAskedForButWaitsForTheDecision() async {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .notDetermined
        let result = await outcome(of: fixer(manager))
        XCTAssertEqual(result, .refused(L.t("place_unavailable")))
        XCTAssertEqual(manager.prompts, 1)
        XCTAssertEqual(manager.requests, 0)
    }

    func testAnUnchangedPermissionIsIgnoredWhileWaiting() async {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .notDetermined
        let fix = fixer(manager, after: .seconds(20))
        let delivery = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            manager.changeAuthorization(to: .notDetermined)
            try? await Task.sleep(for: .milliseconds(60))
            manager.changeAuthorization(to: .authorizedWhenInUse)
            try? await Task.sleep(for: .milliseconds(40))
            manager.deliver([CLLocation(latitude: 52.5163, longitude: 13.3777)])
        }
        let result = await outcome(of: fix)
        XCTAssertEqual(result, .fixed("52.5163,13.3777"))
        await delivery.value
    }

    func testAGrantedPermissionFollowsWithTheRequest() async {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .notDetermined
        let fix = fixer(manager, after: .seconds(20))
        let delivery = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            manager.changeAuthorization(to: .authorizedWhenInUse)
            try? await Task.sleep(for: .milliseconds(40))
            manager.deliver([CLLocation(latitude: 52.5163, longitude: 13.3777)])
        }
        let result = await outcome(of: fix)
        XCTAssertEqual(result, .fixed("52.5163,13.3777"))
        XCTAssertEqual(manager.prompts, 1)
        XCTAssertEqual(manager.requests, 1)
        await delivery.value
    }

    func testADeniedPermissionAfterThePromptRefusesTheWait() async {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .notDetermined
        let fix = fixer(manager, after: .seconds(20))
        let refusal = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            manager.changeAuthorization(to: .denied)
        }
        let result = await outcome(of: fix)
        XCTAssertEqual(result, .refused(L.t("place_denied")))
        XCTAssertEqual(manager.requests, 0)
        await refusal.value
    }

    func testAReportedPositionEndsTheWaitAndIsHandedBack() async {
        let manager = FakeLocationManager()
        let fix = fixer(manager, after: .seconds(20))
        let delivery = handBack(manager, [CLLocation(latitude: 52.5163, longitude: 13.3777)],
                                after: .milliseconds(40))
        let result = await outcome(of: fix)
        XCTAssertEqual(result, .fixed("52.5163,13.3777"))
        await delivery.value
    }

    func testAnEmptyLocationCallbackReleasesTheWaiterAsUnavailable() async {
        let manager = FakeLocationManager()
        let fix = fixer(manager, after: .seconds(20))
        let delivery = handBack(manager, [], after: .milliseconds(40))
        let result = await outcome(of: fix)
        XCTAssertEqual(result, .refused(L.t("place_unavailable")))
        await delivery.value
    }

    func testARefusalFromTheManagerCarriesThePermissionAnswer() async {
        let manager = FakeLocationManager()
        let fix = fixer(manager, after: .seconds(20))
        let refusal = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            manager.refuse(CLError(CLError.denied))
        }
        let result = await outcome(of: fix)
        XCTAssertEqual(result, .refused(L.t("place_denied")))
        await refusal.value
    }

    func testASecondRequestWhileOneIsRunningIsRefusedAsBusy() async {
        let manager = FakeLocationManager()
        let fix = fixer(manager, after: .seconds(20))
        let running = Task { @MainActor in _ = try? await fix.fix() }
        try? await Task.sleep(for: .milliseconds(40))
        let second = await outcome(of: fix, patience: .seconds(2))
        XCTAssertEqual(second, .refused(L.t("place_busy")))
        manager.deliver([CLLocation(latitude: 52.5163, longitude: 13.3777)])
        await running.value
    }

    func testTheAccessStateIsReadable() {
        let manager = FakeLocationManager()
        let fix = fixer(manager, after: .seconds(5))
        XCTAssertEqual(fix.accessState,
                       "\(manager.authorizationStatus.rawValue)/\(manager.accuracyAuthorization.rawValue)")
    }
}
