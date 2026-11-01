@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

extension DebugFeatureProbe {
    static func calendarWrite() async {
        let report = SweepReport(file: "calendar_write.txt")
        guard let morning = probeDate(daysAhead: 1, hour: 9, minute: 0) else {
            report.add("KALENDER", "kein datum")
            return
        }
        let created = "GwenMobile Selbsttest"
        let renamed = "GwenMobile Selbsttest 2"
        var create = QwenAPI.CalendarPlan(action: .create)
        create.title = created
        create.start = Formatters.eventDateTime(morning)
        create.end = Formatters.eventDateTime(morning.addingTimeInterval(3600))
        create.location = "Werkstatt"
        create.alerts = [10, 60]
        do {
            let info = try await CalendarService.perform(create)
            let chip = info.ref?.eventID ?? "-"
            report.add("KALENDER_ANLEGEN", "hinweis=\(TextLine.oneLine(info.notice, limit: 160)) chip=\(chip) im_kontext=\(CalendarService.upcomingContext().contains(created))")
            var update = QwenAPI.CalendarPlan(action: .update)
            update.find = created
            update.title = renamed
            update.alerts = [30]
            let changed = try await CalendarService.perform(update)
            let veranderterChip = changed.ref?.eventID ?? "-"
            report.add("KALENDER_ÄNDERN", "hinweis=\(TextLine.oneLine(changed.notice, limit: 160)) chip=\(veranderterChip) chip_live=\(CalendarService.isLive(veranderterChip)) im_kontext=\(CalendarService.upcomingContext().contains(renamed))")
            var remove = QwenAPI.CalendarPlan(action: .delete)
            remove.find = renamed
            let gone = try await CalendarService.perform(remove)
            report.add("KALENDER_LÖSCHEN", "hinweis=\(TextLine.oneLine(gone.notice, limit: 160)) chip=\(gone.ref?.eventID ?? "keiner") im_kontext=\(CalendarService.upcomingContext().contains(renamed))")
        } catch {
            report.addFailure("KALENDER", error)
        }
        flowLog.info("KALENDER fertig")
    }

    static func calendarGuard() async {
        let report = SweepReport(file: "calendar_guard.txt")
        guard let morning = probeDate(daysAhead: 2, hour: 8, minute: 30) else {
            report.add("KALENDERGUARD", "kein datum")
            return
        }
        let bewacht = "GwenMobile Wächter"
        let fremdwort = "GwenMobileFehlanzeigeUnwort"
        var create = QwenAPI.CalendarPlan(action: .create)
        create.title = bewacht
        create.start = Formatters.eventDateTime(morning)
        create.end = Formatters.eventDateTime(morning.addingTimeInterval(1800))
        create.location = "Werkstatt"
        do {
            let info = try await CalendarService.perform(create)
            report.add("ANGELEGT", "hinweis=\(TextLine.oneLine(info.notice, limit: 160)) im_kontext=\(CalendarService.upcomingContext().contains(bewacht))")
            let vorherDa = CalendarService.upcomingContext().contains(bewacht)
            for (section, plan) in unmatchedPlans(fremdwort: fremdwort) {
                do {
                    let outcome = try await CalendarService.perform(plan)
                    report.add(section, "FEHLER_ERWARTET aber ausführbar: \(TextLine.oneLine(outcome.notice, limit: 160))")
                } catch {
                    report.add(section, "abgewehrt=\(TextLine.oneLine(error.localizedDescription, limit: 160)) termin_noch_da=\(vorherDa && CalendarService.upcomingContext().contains(bewacht))")
                }
            }
            var clean = QwenAPI.CalendarPlan(action: .delete)
            clean.find = bewacht
            let gone = try await CalendarService.perform(clean)
            report.add("AUFRÄUMEN", "hinweis=\(TextLine.oneLine(gone.notice, limit: 160)) noch_im_kontext=\(CalendarService.upcomingContext().contains(bewacht))")
        } catch {
            report.addFailure("KALENDERGUARD", error)
        }
        flowLog.info("KALENDERGUARD fertig")
    }

    static func probeDate(daysAhead: Int, hour: Int, minute: Int) -> Date? {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: daysAhead, to: Date()) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    static func unmatchedPlans(fremdwort: String) -> [(String, QwenAPI.CalendarPlan)] {
        var remove = QwenAPI.CalendarPlan(action: .delete)
        remove.find = fremdwort
        var change = QwenAPI.CalendarPlan(action: .update)
        change.find = fremdwort
        change.title = "GwenMobile überschrieben"
        change.start = "2030-01-01 00:00"
        return [("FALSCHER_LÖSCHVERSUCH", remove), ("FALSCHER_ÄNDERUNGSVERSUCH", change)]
    }

    static func calendarFlow(_ view: ChatView) async {
        let report = SweepReport(file: "calendar_flow.txt")
        let merkmal = "Zahnarzt"
        view.store.newConversation()
        view.input = "Trag morgen um 14 Uhr einen \(merkmal)termin für eine Stunde ein, mit Hinweis 10 Minuten vorher."
        let started = ContinuousClock.now
        await view.send()
        let angelegt = view.store.current?.messages.last(where: { $0.role == .assistant })?.text ?? ""
        let chatChip = view.store.current?.messages.last(where: { $0.role == .assistant })?.calendarRef?.logSummary ?? "keiner"
        let exakt = angelegt.components(separatedBy: "angelegt: ").dropFirst().first?
            .components(separatedBy: " —").first ?? ""
        report.add("KETTE_ANLEGEN", "ms=\(msOf(started.duration(to: .now))) titel=\(exakt.isEmpty ? "-" : exakt) chat_chip=\(chatChip) "
                   + "im_kontext=\(CalendarService.upcomingContext().contains(merkmal)) antwort=\(TextLine.oneLine(angelegt, limit: 160))")
        view.input = "Lösche den Termin bitte wieder."
        let entfernt = ContinuousClock.now
        await view.send()
        let loeschText = view.store.current?.messages.last(where: { $0.role == .assistant })?.text ?? ""
        let chipWeg = view.store.current?.messages.last(where: { $0.role == .assistant })?.calendarRef == nil
        report.add("KETTE_LÖSCHEN", "ms=\(msOf(entfernt.duration(to: .now))) chip_nach_dem_löschen=\(chipWeg ? "keins" : "noch da") noch_im_kontext=\(CalendarService.upcomingContext().contains(merkmal)) antwort=\(TextLine.oneLine(loeschText, limit: 160))")
        if CalendarService.upcomingContext().contains(merkmal), !exakt.isEmpty {
            var cleanup = QwenAPI.CalendarPlan(action: .delete)
            cleanup.find = exakt
            do {
                let aufgeraeumt = try await CalendarService.perform(cleanup)
                report.add("AUFRÄUMEN", "hinweis=\(TextLine.oneLine(aufgeraeumt.notice, limit: 160)) noch_im_kontext=\(CalendarService.upcomingContext().contains(merkmal))")
            } catch {
                report.addFailure("AUFRÄUMEN", error)
            }
        }
        flowLog.info("KALENDERKETTE fertig")
    }

}
#endif
