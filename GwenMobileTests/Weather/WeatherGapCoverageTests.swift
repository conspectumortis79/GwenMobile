@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import UIKit
import XCTest
import GwenMobileKit

final class WeatherGapCoverageTests: GwenTestCase {
    func testEveryWeatherCodeMapsAndEveryKindHasASymbol() {
        XCTAssertEqual(WeatherKind.wmo(0), .sun)
        XCTAssertEqual(WeatherKind.wmo(2), .partly)
        XCTAssertEqual(WeatherKind.wmo(3), .cloud)
        XCTAssertEqual(WeatherKind.wmo(48), .fog)
        XCTAssertEqual(WeatherKind.wmo(55), .drizzle)
        XCTAssertEqual(WeatherKind.wmo(65), .rain)
        XCTAssertEqual(WeatherKind.wmo(67), .heavyRain)
        XCTAssertEqual(WeatherKind.wmo(86), .snow)
        XCTAssertEqual(WeatherKind.wmo(81), .rain)
        XCTAssertEqual(WeatherKind.wmo(99), .storm)
        XCTAssertEqual(WeatherKind.wmo(1234), .cloud)
        for code in [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67,
                     71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99] {
            XCTAssertFalse(WeatherKind.wmo(code).symbol.isEmpty, "\(code)")
        }
        XCTAssertTrue(WeatherKind.storm.isStorm)
        XCTAssertTrue(WeatherKind.heavyRain.isHeavy)
        XCTAssertTrue(WeatherKind.drizzle.isWet)
        XCTAssertFalse(WeatherKind.sun.isWet)
    }

    func testTheLenientWeatherDecodingFallsBackToZero() throws {
        let hour = try JSONDecoder().decode(WeatherHour.self, from: Data("{}".utf8))
        XCTAssertEqual(hour.hour, 0)
        XCTAssertEqual(hour.temp, 0)
        XCTAssertEqual(hour.rain, 0)
        XCTAssertEqual(hour.gust, 0)
        XCTAssertEqual(hour.kind, .cloud)
        let ref = try JSONDecoder().decode(WeatherRef.self, from: Data("{}".utf8))
        XCTAssertEqual(ref.place, "")
        XCTAssertEqual(ref.latitude, 0)
        XCTAssertEqual(ref.longitude, 0)
        XCTAssertEqual(ref.day, "")
        XCTAssertTrue(ref.hours.isEmpty)
        XCTAssertFalse(ref.isOpenable)
        XCTAssertEqual(ref.placeValue.name, "")
    }

    func testTheWeatherDayIndicesAndTabs() {
        XCTAssertEqual(WeatherRequest.Day.today.index, 0)
        XCTAssertEqual(WeatherRequest.Day.tomorrow.index, 1)
        XCTAssertEqual(WeatherRequest.Day.dayAfter.index, 2)
        XCTAssertEqual(WeatherRequest.Day.at(index: 0), .today)
        XCTAssertEqual(WeatherDayTabs.offset(of: "kein datum"), 0)
        XCTAssertEqual(WeatherDayTabs.offset(of: ""), 0)
        XCTAssertFalse(WeatherDayTabs.dates(selected: "kein datum").isEmpty)
        XCTAssertFalse(WeatherDayTabs.stamp(Date()).isEmpty)
    }

    func testTheAdviceLevelsCompare() {
        XCTAssertTrue(WeatherAdvice.Level.green < .orange)
        XCTAssertTrue(WeatherAdvice.Level.orange < .red)
        XCTAssertFalse(WeatherAdvice.Level.red < .green)
        XCTAssertEqual([WeatherAdvice.Level.red, .green, .orange].sorted(), [.green, .orange, .red])
    }

    func testTheDayTitleWithoutAParseableDate() {
        XCTAssertEqual(WeatherAnswers.dayTitle("kein datum"), "kein datum")
    }

    @MainActor
    func testTheScrubViewReadsItsGestures() {
        let view = WeatherScrubView(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
        view.hours = [6, 7, 8]
        var picked: Int?
        view.onSelect = { picked = $0 }
        view.probeSelect(atX: 10)
        XCTAssertNotNil(picked)
        _ = view.perform(NSSelectorFromString("handleTap:"), with: UITapGestureRecognizer())
        _ = view.perform(NSSelectorFromString("handlePan:"), with: UIPanGestureRecognizer())
        XCTAssertTrue(view.gestureRecognizerShouldBegin(UITapGestureRecognizer()))
        XCTAssertFalse(view.gestureRecognizerShouldBegin(UIPanGestureRecognizer()))
        XCTAssertTrue(view.shouldScrub(velocity: CGPoint(x: 10, y: 1)))
        XCTAssertFalse(view.shouldScrub(velocity: CGPoint(x: 1, y: 10)))
        XCTAssertTrue(view.gestureRecognizer(UITapGestureRecognizer(),
                                             shouldRecognizeSimultaneouslyWith: UITapGestureRecognizer()))
        XCTAssertNotNil(Self.archivedCopy(view))
        let empty = WeatherScrubView(frame: .zero)
        XCTAssertNil(empty.probeHour(atX: 5))
    }

    @MainActor
    private static func archivedCopy(_ view: WeatherScrubView) -> WeatherScrubView? {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: view, requiringSecureCoding: false),
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        let copy = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? WeatherScrubView
        unarchiver.finishDecoding()
        return copy
    }
}
