@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import EventKit
import Foundation

@MainActor
struct ProbeCalendarSweeper {
    static let windowDays = 4.0

    private let store = EKEventStore()

    func eventsCreated(since start: Date) -> [EKEvent] {
        guard CalendarService.hasAccess else { return [] }
        let from = Calendar.current.startOfDay(for: start)
        let until = from.addingTimeInterval(Self.windowDays * CalendarService.secondsPerDay)
        let predicate = store.predicateForEvents(withStart: from, end: until, calendars: nil)
        return store.events(matching: predicate).filter { ($0.creationDate ?? .distantPast) >= start }
    }

    func sweep(created refs: [CalendarRef], since start: Date, report: SweepReport, label: String) {
        let own = Set(refs.map(\.eventID).filter { !$0.isEmpty })
        let foreign = eventsCreated(since: start).filter { !own.contains($0.eventIdentifier ?? "") }
        for ref in refs where !ref.eventID.isEmpty {
            let gone = (try? CalendarService.remove(eventID: ref.eventID)) ?? false
            report.add("\(label)_AUFRÄUMEN", "titel=\(ref.title) "
                       + "start=\(Formatters.eventDateTime(ref.start)) weg=\(gone)")
        }
        for event in foreign {
            report.add("\(label)_FREMD", "titel=\(event.title ?? "-") "
                       + "start=\(Formatters.eventDateTime(event.startDate)) bleibt=true")
        }
    }
}
#endif
