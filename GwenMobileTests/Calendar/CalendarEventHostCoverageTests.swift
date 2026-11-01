@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import EventKit
import EventKitUI
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class CalendarEventHostCoverageTests: GwenTestCase {
    func testTheFallbackHostClosesItself() async throws {
        var dismissed = false
        let host = CalendarEventHost(event: nil, closeTitle: "Fertig", fallbackText: "Termin weg",
                                     onDismiss: { dismissed = true })
        host.loadViewIfNeeded()
        host.viewDidLoad()
        host.viewDidAppear(false)
        XCTAssertTrue(dismissed)
        host.setOnDismiss { dismissed = true }
        host.eventViewController(EKEventViewController(), didCompleteWith: .done)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(dismissed)
    }

    func testTheHostShowsALiveEvent() async throws {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Zahnarzt"
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(600)
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Privat"
        event.calendar = calendar
        let host = CalendarEventHost(event: event, closeTitle: "Fertig", fallbackText: "weg",
                                     onDismiss: {})
        host.loadViewIfNeeded()
        host.viewDidLoad()
        host.viewDidAppear(false)
        XCTAssertNotNil(host.topViewController)
    }

    func testTheWrapperHosts() async throws {
        let ref = CalendarRef(eventID: "unbekannt", title: "Termin", start: Date())
        let controller = mountView(CalendarEventView(ref: ref, onDismiss: {}),
                                   size: CGSize(width: 390, height: 600))
        try await settleHosted(controller, milliseconds: 300)
        XCTAssertNotNil(controller.view.window)
    }
}
