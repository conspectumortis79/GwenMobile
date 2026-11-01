@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import EventKit
import Foundation

@MainActor
final class ProbeReminderStore: ReminderStoring {
    var granted = true
    var listTitles = ["Erinnerungen", "Einkauf"]
    var defaultTitle: String? = "Erinnerungen"
    var stored: [StoredReminder] = []
    var coordinates: [String: GeoPoint] = [:]
    private var counter = 0

    func hasAccess() async -> Bool { granted }

    func lists() async -> [String] { listTitles }

    func defaultListTitle() async -> String? { defaultTitle }

    func open() async throws -> [StoredReminder] { stored.filter { !$0.isCompleted } }

    func create(_ draft: ReminderDraft) async throws -> StoredReminder {
        counter += 1
        let made = StoredReminder(id: "probe-\(counter)",
                                  title: draft.title ?? "",
                                  list: draft.list ?? defaultTitle ?? "",
                                  notes: draft.notes ?? "",
                                  due: draft.due,
                                  allDay: draft.allDay,
                                  priority: draft.priority,
                                  place: draft.place?.name,
                                  proximity: draft.place?.proximity,
                                  repeatRule: draft.repeatRule)
        if let point = draft.coordinates { coordinates[made.id] = point }
        stored.append(made)
        flowMark("ERINNERUNG probe haelt den eintrag fest titel=\(made.title) liste=\(made.list) "
                 + "ort=\(made.place ?? "-")")
        return made
    }

    func update(_ id: String, with draft: ReminderDraft) async throws -> StoredReminder {
        guard let index = stored.firstIndex(where: { $0.id == id }) else {
            throw APIError(message: L.t("rem_gone"))
        }
        var item = stored[index]
        if let title = draft.title { item.title = title }
        if let list = draft.list { item.list = list }
        if let notes = draft.notes { item.notes = notes }
        if let due = draft.due {
            item.due = due
            item.allDay = draft.allDay
        }
        if let rule = draft.repeatRule { item.repeatRule = rule }
        if let priority = draft.priority { item.priority = priority }
        if let place = draft.place {
            item.place = place.name
            item.proximity = place.proximity
        }
        if let point = draft.coordinates { coordinates[id] = point }
        stored[index] = item
        return item
    }

    func complete(_ id: String, at date: Date) async throws -> StoredReminder {
        guard let index = stored.firstIndex(where: { $0.id == id }) else {
            throw APIError(message: L.t("rem_gone"))
        }
        stored[index].isCompleted = true
        return stored[index]
    }

    func delete(_ id: String) async throws {
        stored.removeAll { $0.id == id }
    }
}

@MainActor
struct ProbePlaceLookup: ReminderPlaceLooking {
    var points: [String: GeoPoint] = [
        "REWE": GeoPoint(latitude: 52.5219, longitude: 13.4132, radius: 150),
        "Post": GeoPoint(latitude: 52.52, longitude: 13.405, radius: 150),
        "Berlin": GeoPoint(latitude: 52.52, longitude: 13.405, radius: 3000),
    ]

    func locate(_ name: String) async -> GeoPoint? {
        let wanted = TextFolding.fold(name)
        guard !wanted.isEmpty else { return nil }
        return points.first { key, _ in
            let candidate = TextFolding.fold(key)
            return candidate == wanted || candidate.contains(wanted) || wanted.contains(candidate)
        }?.value
    }
}

@MainActor
enum DebugReminderProbe {
    private struct RouteCase: RouteSweep.KindedCase {
        let sentence: String
        let kind: SendStepKind
        var action: ReminderRequest.Action?
        var title: String?
        var notes: String?
        var list: String?
        var place: String?
        var listMustStayEmpty = false
        var history: [ChatMessage] = []
    }

    private static let routeCases = [
        RouteCase(sentence: "Erinnere mich morgen um 9 an den Zahnarzt", kind: .reminder,
                  action: .create, title: "zahnarzt"),
        RouteCase(sentence: "Erinnere mich täglich um 8 Uhr an die Tabletten", kind: .reminder,
                  action: .create, title: "tabletten"),
        RouteCase(sentence: "Setz Milch auf die Einkaufsliste", kind: .reminder,
                  action: .create, title: "milch", list: "einkauf"),
        RouteCase(sentence: "Sag mir Bescheid, wenn ich bei REWE bin, dass ich Milch mitnehme",
                  kind: .reminder, action: .create, title: "milch", place: "REWE"),
        RouteCase(sentence: "Erinnere mich, wenn ich im REWE bin, Milch zu kaufen",
                  kind: .reminder, action: .create, title: "milch", place: "REWE"),
        RouteCase(sentence: "Erinnere mich daran, wenn ich in Berlin bin, dass ich zum MediaMarkt gehen wollte",
                  kind: .reminder, action: .create, title: "mediamarkt", place: "Berlin"),
        RouteCase(sentence: "Erinnere mich, wenn ich in der Nähe einer Post bin, den Brief abzuschicken",
                  kind: .reminder, action: .create, title: "brief", place: "post"),
        RouteCase(sentence: "Was steht auf der Einkaufsliste?", kind: .reminder,
                  action: .list, list: "einkauf"),
        RouteCase(sentence: "Hak Milch ab", kind: .reminder, action: .complete, title: "milch"),
        RouteCase(sentence: "Lösche die Erinnerung an den Zahnarzt", kind: .reminder,
                  action: .delete, title: "zahnarzt"),
        RouteCase(sentence: "Erstelle mir einen Termin für morgen 9 Uhr mit dem Namen ProbeDoc", kind: .calendar),
        RouteCase(sentence: "Lege mir einen Termin an für 11:00 Uhr", kind: .calendar),
        RouteCase(sentence: "Erstelle eine Erinnerung für 11:00 Uhr", kind: .reminder, action: .create),
        RouteCase(sentence: "erstelle mir eine Erinnerung mit dem Namen Arbeit. Der Inhalt soll sein, "
                  + "dass ich morgen noch die Review vorbereiten muss",
                  kind: .reminder, action: .create, title: "arbeit", notes: "review", listMustStayEmpty: true),
        RouteCase(sentence: "erstelle mir eine Erinnerung mit dem Namen Arbeit. Der Inhalt soll sein, "
                  + "dass ich morgen noch die Review vorbereiten muss",
                  kind: .reminder, action: .create, title: "arbeit", notes: "review", listMustStayEmpty: true,
                  history: calendarHistory),
        RouteCase(sentence: "erstelle mir eine Erinnerung mit dem Namen für die Arbeit mit Inhalt. "
                  + "Ich muss morgen unbedingt noch die Reviewvorbereitung machen",
                  kind: .reminder, action: .create, title: "arbeit", listMustStayEmpty: true,
                  history: calendarHistory),
        RouteCase(sentence: "Wie spät ist es?", kind: .clock),
    ]

    private static let calendarHistory = [
        ChatMessage(role: .user,
                    text: "Erstelle mir einen Termin für morgen 12:00 Uhr mit dem Namen Mama Tür öffnen "
                    + "im Kalender Arbeit"),
        ChatMessage(role: .assistant,
                    text: "Termin angelegt für Mama Tür öffnen am Montag 12:00. Kalender: Arbeit. "
                    + "Hinweise: 30 Min vorher")
    ]

    static func routing(_ view: ChatView) async {
        await RouteSweep.routeAllKinded(routeCases, file: "reminder_route.txt", view: view,
                                        log: "ERINNERUNGSROUTING fertig",
                                        history: { $0.history }, fits: fitting, detail: describe)
    }

    private static func fitting(_ item: RouteCase, plan: SendPlan) -> Bool {
        guard plan.primary.stepKind == item.kind else { return false }
        let kinds = Set(plan.actions.map(\.stepKind))
        if item.kind == .calendar, kinds.contains(.reminder) { return false }
        if item.kind == .reminder, kinds.contains(.calendar) { return false }
        guard case .reminder(let request) = plan.primary.route else { return item.kind != .reminder }
        if let action = item.action, request.action != action { return false }
        if let title = item.title {
            let named = request.action == .create ? request.title
                : (request.find.isEmpty ? request.title : request.find)
            if !TextFolding.fold(named).contains(TextFolding.fold(title)) { return false }
        }
        if let notes = item.notes,
           !TextFolding.fold(request.notes ?? "").contains(TextFolding.fold(notes)) { return false }
        if item.listMustStayEmpty, request.list?.isEmpty == false { return false }
        if let list = item.list,
           TextFolding.fold(request.list ?? "").contains(TextFolding.fold(list)) == false { return false }
        if let place = item.place,
           TextFolding.fold(request.place?.name ?? "").contains(TextFolding.fold(place)) == false { return false }
        return true
    }

    private static func describe(_ plan: SendPlan) -> String {
        guard case .reminder(let request) = plan.primary.route else { return plan.traceLine }
        return "\(request.action.rawValue):\(request.title)|liste=\(request.list ?? "-")"
            + "|inhalt=\(request.notes ?? "-")|ort=\(request.place?.name ?? "-")"
    }

    private static func response(_ calls: [(String, [String: Any])]) -> Data {
        let toolCalls = calls.map { name, args -> [String: Any] in
            let arguments = (try? JSONSerialization.data(withJSONObject: args))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return ["id": name, "type": "function", "function": ["name": name, "arguments": arguments]]
        }
        let message: [String: Any] = ["tool_calls": toolCalls, "content": NSNull()]
        let body: [String: Any] = ["choices": [["message": message]]]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    private static func outcomes(_ calls: [(String, [String: Any])],
                                 runner: ReminderFlowRunner) async -> [ReminderFlowOutcome] {
        var made: [ReminderFlowOutcome] = []
        for decision in ToolRouter.decisions(from: response(calls)) {
            guard case .reminder(let request) = decision.route else { continue }
            made.append(await runner.run(request))
        }
        return made
    }

    static func decode() async {
        let report = SweepReport(file: "reminder_decode.txt")
        let store = ProbeReminderStore()
        let runner = ReminderFlowRunner(store: store, places: ProbePlaceLookup())
        var right = 0
        var total = 0

        func finish(_ label: String, _ fits: Bool, _ detail: String) {
            total += 1
            right += fits ? 1 : 0
            report.add("FALL_\(label)", "passt=\(fits) \(detail)")
        }

        let nine = DebugFeatureProbe.tomorrowAt(9)
        let due = Formatters.eventDateTime(nine)

        _ = await outcomes([(ToolRouter.reminderTool,
                             ["action": "create", "title": "Zahnarzt", "due": due])], runner: runner)
        finish("termin", store.stored.contains { $0.title == "Zahnarzt" && $0.due != nil },
               "eintraege=\(store.stored.count)")

        _ = await outcomes([
            (ToolRouter.reminderTool, ["action": "create", "title": "Milch", "list": "Einkauf"]),
            (ToolRouter.reminderTool, ["action": "create", "title": "Brot", "list": "Einkauf"]),
        ], runner: runner)
        let shopping = store.stored.filter { $0.list == "Einkauf" }
        finish("einkauf", shopping.count == 2,
               "artikel=\(shopping.map(\.title).joined(separator: ","))")

        _ = await outcomes([(ToolRouter.reminderTool,
                             ["action": "create", "title": "Milch mitnehmen", "location": "REWE"])], runner: runner)
        finish("standort", store.stored.contains { $0.place == "REWE" && $0.proximity == .arrive },
               "koordinaten=\(store.coordinates.count)")

        _ = await outcomes([(ToolRouter.reminderTool,
                             ["action": "create", "title": "Timer", "minutes": 10])], runner: runner)
        let timer = store.stored.first { $0.title == "Timer" }
        finish("timer", timer?.due.map { $0.timeIntervalSinceNow > 540 && $0.timeIntervalSinceNow < 660 } ?? false,
               "rest=\(Int(timer?.due?.timeIntervalSinceNow ?? -1))s")

        _ = await outcomes([(ToolRouter.reminderTool,
                             ["action": "create", "title": "Timer", "seconds": 10])], runner: runner)
        let shortTimer = store.stored.last { $0.title == "Timer" }
        finish("sekundentimer",
               shortTimer?.due.map { $0.timeIntervalSinceNow > 5 && $0.timeIntervalSinceNow < 20 } ?? false,
               "rest=\(Int(shortTimer?.due?.timeIntervalSinceNow ?? -1))s")

        _ = await outcomes([(ToolRouter.reminderTool,
                             ["action": "complete", "find": "Milch", "list": "Einkauf"])], runner: runner)
        finish("abhaken", store.stored.contains { $0.title == "Milch" && $0.isCompleted },
               "offen=\(store.stored.filter { !$0.isCompleted }.count)")

        let listed = await outcomes([(ToolRouter.reminderTool, ["action": "list", "list": "Einkauf"])],
                                    runner: runner)
        finish("liste", listed.first?.trace.contains("anzahl=") ?? false,
               "spur=\(listed.first?.trace ?? "-")")

        _ = await outcomes([(ToolRouter.reminderTool,
                             ["action": "update", "find": "Brot", "due": due])], runner: runner)
        finish("aendern", store.stored.first { $0.title == "Brot" }?.due != nil,
               "termin=\(store.stored.first { $0.title == "Brot" }?.due != nil)")

        _ = await outcomes([(ToolRouter.reminderTool, ["action": "delete", "find": "Zahnarzt"])], runner: runner)
        finish("loeschen", !store.stored.contains { $0.title == "Zahnarzt" },
               "eintraege=\(store.stored.count)")

        report.add("SUMME", "richtig=\(right)/\(total)")
        flowLog.info("ERINNERUNGSDEKODIERUNG fertig")
    }

    static let flowSentences = [
        "Erinnere mich morgen um 9 an den Zahnarzt",
        "Setz Milch und Brot auf die Einkaufsliste",
        "Sag mir Bescheid, wenn ich bei REWE bin, dass ich Milch mitnehme",
        "Hak Milch ab",
        "Was steht auf der Einkaufsliste?",
        "Erinnere mich, wenn ich im REWE bin, Milch, Brot und Eier zu kaufen",
        "Erinnere mich daran, wenn ich in Berlin bin, dass ich zum MediaMarkt gehen wollte",
        "Erinnere mich, wenn ich in der Nähe einer Post bin, den Brief abzuschicken bzw. mein Paket abzuholen",
    ]

    static func flow(_ view: ChatView) async {
        let report = SweepReport(file: "reminder_flow.txt")
        let store = ProbeReminderStore()
        let known = Set(view.store.conversations.map(\.id))
        let previous = view.store.currentID
        view.reminderDesk.stand(in: store, places: ProbePlaceLookup())
        report.add("KONFIG", "faelle=\(flowSentences.count) schluessel=\(view.settings.isConfigured)")
        var right = 0
        for (index, sentence) in flowSentences.enumerated() {
            let started = ContinuousClock.now
            let answer = await view.ask(sentence, fresh: true)
            let fits = flowFits(index, store: store, answer: answer)
            right += fits ? 1 : 0
            report.add("FALL_\(index + 1)",
                       "passt=\(fits) eintraege=\(store.stored.count) offen=\(store.stored.filter { !$0.isCompleted }.count) "
                       + "ms=\(msOf(started.duration(to: .now))) antwort=\(TextLine.oneLine(answer?.text ?? "", limit: 160)) "
                       + "satz=\(sentence)")
        }
        view.reminderDesk.restore()
        let removed = DebugFeatureProbe.cleanUpProbeConversations(view, keeping: known, restore: previous)
        report.add("AUFRAEUMEN", "probe_chats_entfernt=\(removed) chats=\(view.store.conversations.count)")
        report.add("SUMME", "richtig=\(right)/\(flowSentences.count)")
        flowLog.info("ERINNERUNGSABLAUF fertig")
    }

    static func live() async {
        let report = SweepReport(file: "reminder_live.txt")
        let store = EventKitReminderStore()
        let granted = await store.hasAccess()
        report.add("STATUS", "erlaubt=\(granted) listen=\((await store.lists()).joined(separator: ", "))")
        guard granted else { return }
        let title = "GwenProbe \(Int(Date().timeIntervalSince1970))"
        do {
            let made = try await store.create(ReminderDraft(title: title, list: nil,
                                                            due: Date().addingTimeInterval(600), allDay: false))
            report.add("ANLEGEN", "ok=true titel=\(made.title) liste=\(made.list) id=\(made.id.prefix(8))")
            let open = try await store.open()
            report.add("LESEN", "gefunden=\(open.contains { $0.id == made.id }) offen=\(open.count)")
            try await store.delete(made.id)
            let after = try await store.open()
            report.add("LOESCHEN", "weg=\(!after.contains { $0.id == made.id }) offen=\(after.count)")
        } catch {
            report.add("FEHLER", TextLine.oneLine(error.localizedDescription, limit: 200))
        }
        flowLog.info("ERINNERUNGSLIVE fertig")
    }

    static func flowFits(_ index: Int, store: ProbeReminderStore, answer: ChatMessage?) -> Bool {
        let text = TextFolding.fold(answer?.text ?? "")
        func at(_ place: String) -> [String] {
            store.stored.filter { TextFolding.fold($0.place ?? "").contains(TextFolding.fold(place)) }
                .map { TextFolding.fold($0.title) }
        }
        switch index {
        case 0:
            return store.stored.contains { TextFolding.fold($0.title) == "zahnarzt" }
        case 1:
            let bought = store.stored.filter { $0.list == "Einkauf" }.map { TextFolding.fold($0.title) }
            return bought.contains("milch") && bought.contains("brot")
        case 2:
            return !at("REWE").isEmpty
        case 3:
            return store.stored.contains { TextFolding.fold($0.title) == "milch" && $0.isCompleted }
        case 4:
            return text.contains("brot") && !text.contains("milch")
        case 5:
            let rewe = at("REWE")
            return ["milch", "brot", "eier"].allSatisfy { word in rewe.contains { $0.contains(word) } }
        case 6:
            return !at("Berlin").isEmpty
        default:
            let post = at("Post")
            return ["brief", "paket"].allSatisfy { word in post.contains { $0.contains(word) } }
        }
    }

    static func lists() async {
        let report = SweepReport(file: "reminder_lists.txt")
        let store = EventKitReminderStore()
        let granted = await store.hasAccess()
        report.add("STATUS", "zugriff=\(EKEventStore.authorizationStatus(for: .reminder).rawValue) "
                   + "erlaubt=\(granted) service_hat_zugriff=\(EventKitReminderStore.hasAccess)")
        let titles = await store.lists()
        report.add("LISTEN", "anzahl=\(titles.count) titel=\(titles.joined(separator: ", "))")
        let open = (try? await store.open()) ?? []
        report.add("OFFEN", "anzahl=\(open.count) mit_ort=\(open.filter { $0.place != nil }.count) "
                   + "mit_datum=\(open.filter { $0.due != nil }.count)")
        flowLog.info("ERINNERUNGSLISTEN fertig")
    }
}
#endif
