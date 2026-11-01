@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Contacts
import CoreLocation
import Foundation
import UserNotifications

@MainActor
private struct ProbeBriefingCalendar: BriefingCalendarReading {
    var events: [DayBriefingEvent]

    func briefingEvents(on day: Date) -> [DayBriefingEvent] {
        events.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }
}

@MainActor
private struct ProbeBriefingReminders: BriefingReminderReading {
    var items: [StoredReminder]

    func briefingReminders() async -> [StoredReminder] { items }
}

@MainActor
private struct ProbeBriefingWeather: BriefingWeatherLoading {
    func briefingWeather(dayOffset: Int) async throws -> WeatherRef {
        let hours = (6...22).map { hour in
            WeatherHour(hour: hour, temp: hour < 12 ? 9 : 14, rain: hour < 12 ? 70 : 0,
                        precip: hour < 12 ? 1.2 : 0, wind: 12, gust: 22, uv: 1,
                        kind: hour < 12 ? .rain : .partly)
        }
        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return WeatherRef(place: "München", latitude: 48.137, longitude: 11.575,
                          day: Formatters.stamp(date),
                          timezone: "Europe/Berlin", hours: hours)
    }
}

@MainActor
private struct ProbeBriefingTravel: BriefingTravelLooking {
    func briefingTravel(to location: String, departure: Date) async -> DayBriefingTravel? {
        DayBriefingTravel(title: location, carMinutes: 18, bikeMinutes: 25)
    }
}

private struct ProbeBriefingContacts: ContactDirectory {
    var cards: [ContactCard]

    func access() async -> ContactAccess { .granted }

    func cards() async throws -> [ContactCard] { cards }
}

@MainActor
enum DebugDayBriefingProbe {
    private enum Expectation {
        case briefing([BriefingDay])
        case calendar
        case price
        case reminder
        case weather
        case other
    }

    private struct BriefingCase {
        let text: String
        let expected: Expectation
        let step: String
    }

    private static let cases = [
        BriefingCase(text: "Was steht heute an?", expected: .briefing([.today]), step: "heute"),
        BriefingCase(text: "Fasse meinen Tag zusammen", expected: .briefing([.today]), step: "heute"),
        BriefingCase(text: "Was ist morgen wichtig?", expected: .briefing([.tomorrow]), step: "morgen"),
        BriefingCase(text: "Was steht übermorgen an?", expected: .briefing([.dayAfter]), step: "uebermorgen"),
        BriefingCase(text: "Wie wird das Wetter morgen?", expected: .weather, step: "wetter"),
        BriefingCase(text: "Erinnere mich morgen um 9 an den Zahnarzt", expected: .reminder,
                     step: "erinnerung"),
        BriefingCase(text: "Trage morgen um 10 Uhr Zahnarzt in den Kalender ein", expected: .calendar,
                     step: "kalender"),
        BriefingCase(text: "Was kostet die PlayStation 5 gerade?", expected: .price, step: "vergleich"),
        BriefingCase(text: "Erzähl mir etwas über München", expected: .other, step: "chat")
    ]

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "day_briefing.txt")
        report.add("KONFIG", "schluessel=\(view.settings.isConfigured) chat=\(view.settings.chatModel) "
                   + "basis=\(view.settings.baseURL) sprache=\(L.lang.rawValue)")
        await routing(view, report: report)
        await fixtures(report: report)
        await flow(view, report: report)
        await live(report: report)
        await notification(report: report)
        flowLog.info("TAGESBRIEFING fertig")
    }

    private static func routing(_ view: ChatView, report: SweepReport) async {
        var right = 0
        var wrongBriefing = 0
        for (index, item) in cases.enumerated() {
            let decision = await ToolRouter.decide(await RouteSweep.ask(view, text: item.text))
            let fits = matches(decision, item)
            if fits { right += 1 }
            if case .dayBriefing = decision?.route, !wantsBriefing(item) { wrongBriefing += 1 }
            report.add("ROUTER_\(index + 1)",
                       "passt=\(fits) erwartet=\(item.step) gewaehlt=\(describe(decision)) "
                       + "satz=\(TextLine.oneLine(item.text, limit: 60))")
        }
        report.add("ROUTER_SUMME", "richtig=\(right)/\(cases.count) briefing_falsch=\(wrongBriefing)")
    }

    private static func fixtures(report: SweepReport) async {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let reference = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: start) ?? start
        func at(_ hour: Int, minute: Int = 0, day: Int = 0) -> Date {
            let base = Calendar.current.date(byAdding: .day, value: day, to: start) ?? start
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        let events = [
            DayBriefingEvent(id: "ev1", title: "Zahnarzt Dr. Berger", start: at(11), end: at(12),
                             location: "Praxis am Ring 12", calendar: "Privat"),
            DayBriefingEvent(id: "ev2", title: "Team-Call", start: at(15), end: at(16),
                             location: "Videokonferenz", calendar: "Arbeit"),
            DayBriefingEvent(id: "ev3", title: "Elternabend", start: at(18), end: at(20),
                             calendar: "Familie"),
            DayBriefingEvent(id: "ev4", title: "Physio", start: at(8, day: 1), end: at(9, day: 1),
                             location: "Praxis Sendling", calendar: "Privat")
        ]
        let parts = Calendar.current.dateComponents([.month, .day], from: now)
        let reminders = [
            StoredReminder(id: "r1", title: "Stadtwerke-Rechnung",
                           list: "Aufgaben", due: at(9, day: -1)),
            StoredReminder(id: "r2", title: "Einkaufsliste", list: "Einkauf", due: nil),
            StoredReminder(id: "r3", title: "Müll rausstellen", list: "Aufgaben", due: at(19))
        ]
        let contacts = ProbeBriefingContacts(cards: [
            ContactCard(id: "papa", name: "Papa", nameParts: ["Papa"],
                        birthday: DateComponents(year: 1963, month: parts.month, day: parts.day))
        ])
        let sources = DayBriefingSources(calendar: ProbeBriefingCalendar(events: events),
                                         reminders: ProbeBriefingReminders(items: reminders),
                                         contacts: contacts,
                                         weather: ProbeBriefingWeather(),
                                         travel: ProbeBriefingTravel())
        let ref = await DayBriefingService(sources: sources, includes: DayBriefingIncludes())
            .build(.today, now: reference)
        report.add("FIXTUR", "datum=\(ref.date) termin_anzahl=\(ref.events.count) "
                   + "erster=\(TextLine.oneLine(ref.events.first?.title ?? "-", limit: 40)) "
                   + "offen=\(ref.reminders.map(\.title).joined(separator: "|")) "
                   + "ueberfaellig=\(ref.reminders.first?.overdue ?? false) "
                   + "geburtstage=\(ref.birthdays.count) fahrzeit=\(ref.travel?.carMinutes ?? -1)/"
                   + "\(ref.travel?.bikeMinutes ?? -1) wetter=\(ref.weather?.hours.count ?? -1) "
                   + "abschluss=\(TextLine.oneLine(ref.closing, limit: 60))")
        let text = DayBriefingAnswers.text(ref)
        report.add("FIXTUR_TEXT", TextLine.oneLine(text, limit: 300))
        report.add("FIXTUR_TEXT_TREFFER",
                   "gruss=\(text.contains(ref.greeting)) termine=\(text.contains("Termine")) "
                   + "zahnarzt=\(text.contains("Zahnarzt")) offen=\(text.contains("Offen:")) "
                   + "geburtstag=\(text.contains("Papa")) wetter=\(text.contains("°C")) "
                   + "einzeilig=\(!DayBriefingAnswers.notificationBody(ref).contains("\n"))")
        let tomorrow = await DayBriefingService(sources: sources, includes: DayBriefingIncludes())
            .build(.tomorrow, now: reference)
        let after = await DayBriefingService(sources: sources, includes: DayBriefingIncludes())
            .build(.dayAfter, now: reference)
        report.add("FIXTUR_TAGE", "morgen_datum=\(tomorrow.date) morgen_gruss=\(tomorrow.greetingKey) "
                   + "morgen_termine=\(tomorrow.events.count) morgen_geburtstage=\(tomorrow.birthdays.count) "
                   + "uebermorgen_gruss=\(after.greetingKey) uebermorgen_termine=\(after.events.count)")
        let off = await DayBriefingService(sources: sources, includes: DayBriefingIncludes(
            weather: false, reminders: false, birthdays: false, travel: false)).build(.today, now: reference)
        report.add("FIXTUR_AUS", "wetter=\(off.weather == nil) fahrzeit=\(off.travel == nil) "
                   + "offen=\(off.reminders.count) geburtstage=\(off.birthdays.count) "
                   + "termine=\(off.events.count)")
    }

    private static func flow(_ view: ChatView, report: SweepReport) async {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        func at(_ hour: Int, day: Int = 0) -> Date {
            let base = Calendar.current.date(byAdding: .day, value: day, to: start) ?? start
            return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        }
        let sources = DayBriefingSources(
            calendar: ProbeBriefingCalendar(events: [
                DayBriefingEvent(id: "ev1", title: "Zahnarzt Dr. Berger", start: at(11), end: at(12),
                                 location: "Praxis am Ring 12", calendar: "Privat"),
                DayBriefingEvent(id: "ev2", title: "Team-Call", start: at(15), end: at(16),
                                 location: "Videokonferenz", calendar: "Arbeit")
            ]),
            reminders: ProbeBriefingReminders(items: [
                StoredReminder(id: "r1", title: "Stadtwerke-Rechnung", list: "Aufgaben", due: at(9, day: -1))
            ]),
            contacts: ProbeBriefingContacts(cards: [
                ContactCard(id: "papa", name: "Papa", nameParts: ["Papa"],
                            birthday: DateComponents(year: 1963, month: 9, day: 1))
            ]),
            weather: ProbeBriefingWeather(),
            travel: ProbeBriefingTravel())
        view.briefingDesk.stand(in: sources)
        let known = Set(view.store.conversations.map(\.id))
        let answer = await view.ask("Was steht heute an?", fresh: true)
        let ref = answer?.dayBriefingRef
        report.add("ABLAUF_ANTWORT", "karte=\(ref != nil) datum=\(ref?.date ?? "-") "
                   + "termine=\(ref?.events.count ?? -1) offen=\(ref?.reminders.count ?? -1) "
                   + "fahrt=\(ref?.travel != nil) wetter=\(ref?.weather != nil) "
                   + "plan=\(view.probeLastPlan?.traceLine ?? "-") "
                   + "text=\(TextLine.oneLine(answer?.text ?? "", limit: 220))")
        if let answer {
            await view.switchBriefingDay(message: answer.id, day: "tomorrow")
            let updated = view.store.current?.messages.first { $0.id == answer.id }
            report.add("ABLAUF_TAGWECHSEL", "datum=\(updated?.dayBriefingRef?.date ?? "-") "
                       + "gruss=\(updated?.dayBriefingRef?.greetingKey ?? "-") "
                       + "termine=\(updated?.dayBriefingRef?.events.count ?? -1) "
                       + "text=\(TextLine.oneLine(updated?.text ?? "", limit: 160))")
        }
        view.briefingDesk.restore()
        var dropped = 0
        for conversation in view.store.conversations where !known.contains(conversation.id) {
            if view.store.removeConversation(conversation.id) != nil { dropped += 1 }
        }
        report.add("AUFRAEUMEN", "probe_chats_entfernt=\(dropped) chats=\(view.store.conversations.count)")
    }

    private static func live(report: SweepReport) async {
        let calendar = CalendarService.hasAccess
        let reminders = EventKitReminderStore.hasAccess
        let contacts = CNContactStore.authorizationStatus(for: .contacts)
        let location = CLLocationManager().authorizationStatus
        report.add("RECHTE", "kalender=\(calendar) erinnerungen=\(reminders) kontakte=\(contacts.rawValue) "
                   + "standort=\(location.rawValue)")
        guard calendar || reminders else {
            report.add("LIVE", "kein zugriff — gerät liefert keine echten tage")
            return
        }
        let ref = await DayBriefingService(sources: .live(), includes: DayBriefingIncludes(
            weather: DayBriefingNotifier.locationAllowed(),
            reminders: true,
            birthdays: DayBriefingNotifier.contactsAllowed(),
            travel: false)).build(.today)
        report.add("LIVE", "datum=\(ref.date) termine=\(ref.events.count) offen=\(ref.reminders.count) "
                   + "geburtstage=\(ref.birthdays.count) wetter=\(ref.weather?.hours.count ?? -1) "
                   + "erster=\(TextLine.oneLine(ref.events.first?.title ?? "-", limit: 50))")
    }

    private static func notification(report: SweepReport) async {
        let settings = AppSettings.shared
        let enabled = settings.briefing.enabled
        let minutes = settings.briefing.minutes
        let sources = DayBriefingSources(
            calendar: ProbeBriefingCalendar(events: [
                DayBriefingEvent(id: "ev1", title: "Zahnarzt", start: Date().addingTimeInterval(3600),
                                 calendar: "Privat")
            ]),
            reminders: ProbeBriefingReminders(items: []),
            contacts: nil, weather: nil, travel: nil)
        settings.briefing.enabled = true
        settings.briefing.minutes = 450
        await DayBriefingNotifier.refresh(sources: sources, force: true)
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let planned = pending.first { DayBriefingNotifier.pendingIdentifiers.contains($0.identifier) }
        let trigger = planned?.trigger as? UNCalendarNotificationTrigger
        report.add("PLANUNG", "ausstehend=\(planned != nil) "
                   + "uhrzeit=\(trigger?.dateComponents.hour ?? -1):\(trigger?.dateComponents.minute ?? -1) "
                   + "wiederholt=\(trigger?.repeats ?? false)")
        let ref = await DayBriefingService(sources: sources, includes: DayBriefingIncludes(
            weather: false, reminders: false, birthdays: false, travel: false)).build(.today)
        DayBriefingNotifier.post(ref)
        _ = await ProbeWait.poll(10) {
            await UNUserNotificationCenter.current().deliveredNotifications()
                .contains { $0.request.identifier.hasPrefix(DayBriefingNotifier.identifier) }
        }
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        let mine = delivered.filter { $0.request.identifier.hasPrefix(DayBriefingNotifier.identifier) }
        report.add("MITTEILUNG", "zugestellt=\(mine.count) "
                   + "titel=\(TextLine.oneLine(mine.first?.request.content.title ?? "-", limit: 60))")
        settings.briefing.enabled = enabled
        settings.briefing.minutes = minutes
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: DayBriefingNotifier.pendingIdentifiers)
        UserDefaults.standard.removeObject(forKey: DayBriefingNotifier.refreshedDayKey)
        report.add("WIEDERHERSTELLUNG", "an=\(settings.briefing.enabled) uhrzeit=\(settings.briefing.minutes)")
    }

    private static func wantsBriefing(_ item: BriefingCase) -> Bool {
        if case .briefing = item.expected { return true }
        return false
    }

    private static func matches(_ decision: ToolDecision?, _ item: BriefingCase) -> Bool {
        guard let decision else {
            if case .other = item.expected { return true }
            return false
        }
        switch (item.expected, decision.route) {
        case (.briefing(let days), .dayBriefing(let request)):
            return days.contains(request.day)
        case (.calendar, .calendar), (.price, .priceSearch), (.reminder, .reminder),
             (.weather, .weather):
            return true
        case (.other, .chat):
            return true
        default:
            return false
        }
    }

    private static func describe(_ decision: ToolDecision?) -> String {
        if case .some(.dayBriefing(let request)) = decision?.route {
            return "briefing/\(request.day.rawValue)"
        }
        return RouteSweep.describe(decision)
    }
}
#endif
