@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class WeatherCardViewTests: GwenTestCase {
    private func variedDay() -> [WeatherHour] {
        WeatherFixture.day { hour in
            switch hour % 4 {
            case 0:
                return WeatherFixture.hour(hour, temp: 11 + Double(hour), rain: 80, precip: 1.4,
                                           wind: 28, gust: 52, uv: 1, kind: .storm)
            case 1:
                return WeatherFixture.hour(hour, temp: 17 + Double(hour), rain: 45, precip: 0.8,
                                           wind: 14, gust: 30, uv: 4, kind: .rain)
            case 2:
                return WeatherFixture.hour(hour, temp: 23 + Double(hour), rain: 20, precip: 0.2,
                                           wind: 8, gust: 16, uv: 7, kind: .partly)
            default:
                return WeatherFixture.hour(hour, temp: 30 + Double(hour), rain: 0, precip: 0,
                                           wind: 5, gust: 12, uv: 9, kind: .sun)
            }
        }
    }

    private func scrubView(in view: UIView, depth: Int = 0) -> WeatherScrubView? {
        if let match = view as? WeatherScrubView { return match }
        guard depth < 30 else { return nil }
        for child in view.subviews {
            if let found = scrubView(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    func testAFullDayDrawsTheWholeCard() async throws {
        let ref = WeatherFixture.ref(hours: variedDay())
        let controller = mountView(WeatherCard(ref: ref, onDay: { _ in }, onSpeak: {}),
                                   size: CGSize(width: 320, height: 760))
        try await settleHosted(controller)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 300, height: 4000)).height, 300)
        XCTAssertNotNil(renderView(WeatherCard(ref: ref, onDay: { _ in }, onSpeak: {}), width: 300))
    }

    func testTheCardDrawsWithoutHours() async throws {
        let ref = WeatherFixture.ref(hours: [])
        let controller = mountView(WeatherCard(ref: ref), size: CGSize(width: 320, height: 600))
        try await settleHosted(controller)
        XCTAssertNotNil(renderView(WeatherCard(ref: ref), width: 300))
    }

    func testTheCardDrawsWithoutActionsAndWithoutAdvice() async throws {
        let mild = WeatherFixture.day { WeatherFixture.hour($0) }
        let ref = WeatherFixture.ref(hours: mild)
        let controller = mountView(WeatherCard(ref: ref, showsActions: false),
                                   size: CGSize(width: 320, height: 600))
        try await settleHosted(controller)
        XCTAssertNotNil(renderView(WeatherCard(ref: ref, showsActions: false), width: 300))
    }

    func testTheProbeBindingDrivesTheSelectedHour() async throws {
        let seen = LockedValue<[Int]>([])
        let card = WeatherCard(ref: WeatherFixture.ref(hours: variedDay()),
                               probeHour: .constant(9), probeHourValue: 9,
                               probeSelectedHour: { value in seen.mutate { $0.append(value) } })
        let controller = mountView(card, size: CGSize(width: 320, height: 760))
        try await settleHosted(controller, milliseconds: 250)
        XCTAssertEqual(seen.current, [9])
    }

    func testTheCurveHandlesEmptyAndSingleHourData() {
        XCTAssertNotNil(renderView(WeatherCurveView(ref: WeatherFixture.ref(hours: []),
                                                    selectedHour: 12, labelSize: 10), width: 300))
        XCTAssertNotNil(renderView(WeatherCurveView(ref: WeatherFixture.ref(hours: [WeatherFixture.hour(12)]),
                                                    selectedHour: 12, labelSize: 10), width: 300))
    }

    func testTheCurveMarksTheSelectedAndTheExtremeHours() {
        let hours = WeatherFixture.day { WeatherFixture.hour($0, temp: $0 == 12 ? 31 : 5 + Double($0)) }
        XCTAssertNotNil(renderView(WeatherCurveView(ref: WeatherFixture.ref(hours: hours),
                                                    selectedHour: 12, labelSize: 10), width: 300))
        let flat = WeatherFixture.day { WeatherFixture.hour($0, temp: 15) }
        XCTAssertNotNil(renderView(WeatherCurveView(ref: WeatherFixture.ref(hours: flat),
                                                    selectedHour: 18, labelSize: 10), width: 300))
    }

    func testTheBarsCoverEveryRainBucket() async throws {
        let hours = [0, 20, 50, 80].enumerated().map { index, rain in
            WeatherFixture.hour(6 + index * 4, rain: rain)
        }
        XCTAssertNotNil(renderView(WeatherBarsView(ref: WeatherFixture.ref(hours: hours), selectedHour: 14),
                                   width: 300))
        let empty = mountView(WeatherBarsView(ref: WeatherFixture.ref(hours: []), selectedHour: 14),
                              size: CGSize(width: 300, height: 60))
        try await settleHosted(empty)
    }

    func testTheHourLabelsRenderOnAndBetweenTheFullHours() async throws {
        let hours = (6...22).map { WeatherFixture.hour($0) }
        XCTAssertNotNil(renderView(WeatherHourLabelsView(ref: WeatherFixture.ref(hours: hours)), width: 300))
        let empty = mountView(WeatherHourLabelsView(ref: WeatherFixture.ref(hours: [])),
                              size: CGSize(width: 300, height: 40))
        try await settleHosted(empty)
    }

    func testTheTilesShowValuesAndFallBackToZero() {
        XCTAssertNotNil(renderView(WeatherTilesView(ref: WeatherFixture.ref(hours: variedDay())), width: 300))
        XCTAssertNotNil(renderView(WeatherTilesView(ref: WeatherFixture.ref(hours: [])), width: 300))
    }

    func testTheIconRowHandlesShortAndLongDays() async throws {
        let short = (6...8).map { WeatherFixture.hour($0, kind: .snow) }
        XCTAssertNotNil(renderView(WeatherIconRow(ref: WeatherFixture.ref(hours: short)), width: 300))
        let long = (6...22).map { WeatherFixture.hour($0) }
        XCTAssertNotNil(renderView(WeatherIconRow(ref: WeatherFixture.ref(hours: long)), width: 300))
        let empty = mountView(WeatherIconRow(ref: WeatherFixture.ref(hours: [])),
                              size: CGSize(width: 300, height: 60))
        try await settleHosted(empty)
    }

    func testTheScrubberReportsTheTouchedHourThroughTheHostedSurface() async throws {
        var picked: Int?
        let hours = WeatherFixture.day { WeatherFixture.hour($0) }
        let controller = mountView(WeatherHourScrubber(ref: WeatherFixture.ref(hours: hours),
                                                       selectedHour: 12, labelSize: 10,
                                                       onSelect: { picked = $0 }),
                                   size: CGSize(width: 320, height: 160))
        try await settleHosted(controller)
        let scrub = try XCTUnwrap(scrubView(in: controller.view), "keine Scrubbing-Fläche im gehosteten Balken")
        scrub.probeSelect(atX: 100)
        XCTAssertEqual(picked, 11)
    }

    func testTheScrubViewPicksTheHourUnderTheFinger() {
        let view = WeatherScrubView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        view.hours = [6, 7, 8, 9]
        var picked: Int?
        view.onSelect = { picked = $0 }
        XCTAssertEqual(view.probeHour(atX: 0), 6)
        XCTAssertEqual(view.probeHour(atX: 160), 9)
        view.probeSelect(atX: 160)
        XCTAssertEqual(picked, 9)
        view.hours = []
        XCTAssertNil(view.probeHour(atX: 10))
        view.probeSelect(atX: 10)
        XCTAssertEqual(picked, 9)
        view.hours = [7]
        XCTAssertEqual(view.probeHour(atX: 199), 7)
    }

    func testTheScrubViewOnlyStartsOnHorizontalPan() {
        let view = WeatherScrubView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        XCTAssertTrue(view.shouldScrub(velocity: CGPoint(x: 30, y: 4)))
        XCTAssertFalse(view.shouldScrub(velocity: CGPoint(x: 2, y: 40)))
        let pan = UIPanGestureRecognizer()
        let tap = UITapGestureRecognizer()
        XCTAssertFalse(view.gestureRecognizerShouldBegin(pan))
        XCTAssertTrue(view.gestureRecognizerShouldBegin(tap))
        XCTAssertTrue(view.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: tap))
    }
}
