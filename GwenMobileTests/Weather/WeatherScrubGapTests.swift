@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class WeatherScrubGapTests: GwenTestCase {
    func testTheHourScrubberStepsAndPicks() async throws {
        let ref = WeatherFixture.ref(hours: WeatherFixture.day { WeatherFixture.hour($0) })
        let selected = LockedValue(0)
        let scrubber = WeatherHourScrubber(ref: ref, selectedHour: ref.hours.first?.hour ?? 6,
                                           labelSize: 10, onSelect: { selected.set($0) })
        scrubber.stepHour(.increment)
        scrubber.stepHour(.decrement)
        let host = mountView(scrubber, size: CGSize(width: 390, height: 260))
        try await settleHosted(host, milliseconds: 150)

        let view = WeatherScrubView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        view.hours = ref.hours.map(\.hour)
        view.onSelect = { selected.set($0) }
        view.pick(at: 0)
        view.pick(at: 10_000)
        XCTAssertFalse(view.hourIndex(at: 0) == nil)
        view.handleTap(UITapGestureRecognizer())
        view.handlePan(UIPanGestureRecognizer())
        XCTAssertFalse(view.gestureRecognizers?.isEmpty ?? true)
    }
}
