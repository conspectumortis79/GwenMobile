@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class DayBriefingCardViewTests: GwenTestCase {
    private func date(_ hour: Int, minute: Int = 0, day: Int = 5) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))
            ?? Date()
    }

    private var rainy: WeatherRef {
        WeatherFixture.ref(hours: WeatherFixture.day {
            WeatherFixture.hour($0, temp: 9 + Double($0 % 5), rain: 70, precip: 1.1,
                                wind: 25, gust: 48, uv: 1, kind: .rain)
        })
    }

    private var mild: WeatherRef {
        WeatherFixture.ref(hours: WeatherFixture.day { WeatherFixture.hour($0, temp: 20) })
    }

    private func full(_ weather: WeatherRef?) -> DayBriefingRef {
        DayBriefingRef(
            date: "2026-10-05",
            greetingKey: "brief_greet_morning",
            weather: weather,
            events: [
                DayBriefingEvent(id: "e1", title: "Zahnarzt", start: date(9), end: date(10),
                                 location: "Praxis", calendar: "Privat",
                                 ref: CalendarRef(eventID: "x1", title: "Zahnarzt", start: date(9))),
                DayBriefingEvent(id: "e2", title: "Teams", start: date(11), calendar: "Arbeit"),
                DayBriefingEvent(id: "e3", title: "Ganztags", start: date(8), allDay: true, calendar: "Arbeit")
            ],
            travel: DayBriefingTravel(title: "Zahnarzt", carMinutes: 18, bikeMinutes: 25),
            reminders: [
                DayBriefingItem(id: "r1", title: "Milch", detail: "Einkauf", badge: "2"),
                DayBriefingItem(id: "r2", title: "Rechnung", detail: "Zahlung offen", overdue: true),
                DayBriefingItem(id: "r3", title: "Notiz", detail: "", badge: "")
            ],
            birthdays: [DayBriefingItem(id: "g1", title: "Anna", detail: "wird 30")],
            closing: "Schönen Tag"
        )
    }

    private var bare: DayBriefingRef {
        DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning")
    }

    func testTheFullCardDrawsEverything() async throws {
        let ref = full(rainy)
        let controller = mountView(DayBriefingCard(ref: ref, onDay: { _ in }, onSpeak: {},
                                                   onNotify: {}, onOpenEvent: { _ in }),
                                   size: CGSize(width: 340, height: 900))
        try await settleHosted(controller)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 300, height: 4000)).height, 400)
        XCTAssertNotNil(renderView(DayBriefingCard(ref: ref), width: 300))
    }

    func testTheCardDrawsWithoutEventsWeatherOrActions() async throws {
        let controller = mountView(DayBriefingCard(ref: bare), size: CGSize(width: 340, height: 500))
        try await settleHosted(controller)
        XCTAssertNotNil(renderView(DayBriefingCard(ref: bare), width: 300))
    }

    func testTheWeatherWithoutAdviceStillDraws() async throws {
        let ref = full(mild)
        let controller = mountView(DayBriefingCard(ref: ref), size: CGSize(width: 340, height: 700))
        try await settleHosted(controller)
        XCTAssertNotNil(renderView(DayBriefingCard(ref: ref), width: 300))
    }

    func testTheTravelReminderAndBirthdayBlocksCanBeEmpty() async throws {
        var ref = full(nil)
        ref.travel = DayBriefingTravel(title: "Büro")
        ref.reminders = []
        ref.birthdays = []
        let controller = mountView(DayBriefingCard(ref: ref), size: CGSize(width: 340, height: 500))
        try await settleHosted(controller)
        XCTAssertNotNil(renderView(DayBriefingCard(ref: ref), width: 300))
    }
}
