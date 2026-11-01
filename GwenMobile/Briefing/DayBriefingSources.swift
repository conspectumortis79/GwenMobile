import GwenMobileKit
import CoreLocation
import EventKit
import Foundation
import MapKit

@MainActor
protocol BriefingCalendarReading {
    func briefingEvents(on day: Date) -> [DayBriefingEvent]
}

@MainActor
protocol BriefingReminderReading {
    func briefingReminders() async -> [StoredReminder]
}

@MainActor
protocol BriefingWeatherLoading {
    func briefingWeather(dayOffset: Int) async throws -> WeatherRef
}

@MainActor
protocol BriefingTravelLooking {
    func briefingTravel(to location: String, departure: Date) async -> DayBriefingTravel?
}

struct LiveBriefingCalendar: BriefingCalendarReading {
    var events: @MainActor (Date) -> [EKEvent] = { CalendarService.events(on: $0) }

    func briefingEvents(on day: Date) -> [DayBriefingEvent] {
        events(day).map { event in
            DayBriefingEvent(id: event.eventIdentifier ?? UUID().uuidString,
                             title: event.title ?? "",
                             start: event.startDate,
                             end: event.endDate,
                             allDay: event.isAllDay,
                             location: event.location?.nilIfEmpty,
                             calendar: event.calendar.title,
                             ref: CalendarService.reference(for: event))
        }
    }
}

struct LiveBriefingReminders: BriefingReminderReading {
    var store: any ReminderStoring = EventKitReminderStore()

    func briefingReminders() async -> [StoredReminder] {
        (try? await store.open()) ?? []
    }
}

struct LiveBriefingWeather: BriefingWeatherLoading {
    var service = WeatherService()

    func briefingWeather(dayOffset: Int) async throws -> WeatherRef {
        try await service.day(for: WeatherRequest(place: nil, day: WeatherRequest.Day.at(index: dayOffset),
                                                  date: nil, offset: dayOffset))
    }
}

@MainActor
final class StubBriefingTravel: BriefingTravelLooking {
    func briefingTravel(to location: String, departure: Date) async -> DayBriefingTravel? { nil }
}

@MainActor
enum BriefingTravelPort {
    nonisolated(unsafe) static var current: any BriefingTravelLooking = StubBriefingTravel()
}

@MainActor
struct DayBriefingSources {
    var calendar: any BriefingCalendarReading
    var reminders: any BriefingReminderReading
    var contacts: (any ContactDirectory)?
    var weather: (any BriefingWeatherLoading)?
    var travel: (any BriefingTravelLooking)?

    static func live() -> DayBriefingSources {
        DayBriefingSources(calendar: LiveBriefingCalendar(), reminders: LiveBriefingReminders(),
                           contacts: LiveContactDirectory(), weather: LiveBriefingWeather(),
                           travel: BriefingTravelPort.current)
    }
}
