import GwenMobileKit
import Foundation

struct ReminderFlowOutcome: Equatable, Sendable {
    let text: String
    let trace: String
    let ref: ReminderRef?
    var changed = false
}

@MainActor
struct ReminderFlowRunner {
    let store: any ReminderStoring
    let places: any ReminderPlaceLooking

    func run(_ request: ReminderRequest) async -> ReminderFlowOutcome {
        guard await store.hasAccess() else {
            return ReminderFlowOutcome(text: L.t("rem_denied"), trace: "zugriff=verweigert", ref: nil)
        }
        switch request.action {
        case .list: return await read(request)
        case .create: return await create(request)
        case .update: return await change(request)
        case .complete: return await complete(request)
        case .delete: return await delete(request)
        }
    }

    private func read(_ request: ReminderRequest) async -> ReminderFlowOutcome {
        do {
            let open = try await store.open()
            let title = await matchedList(request.list)
            let wanted = title.map { name in open.filter { $0.list == name } } ?? open
            return ReminderFlowOutcome(text: ReminderAnswer.list(wanted, titled: title),
                                       trace: "aktion=list liste=\(title ?? "-") anzahl=\(wanted.count)",
                                       ref: nil)
        } catch {
            return failure(error, action: "list")
        }
    }

    private func create(_ request: ReminderRequest) async -> ReminderFlowOutcome {
        do {
            let list = try await creationList(request.list)
            var draft = ReminderDraft(title: request.title, list: list, notes: request.notes,
                                      due: request.due, allDay: request.allDay,
                                      repeatRule: request.repeatRule, priority: request.priority,
                                      place: request.place)
            if let outcome = await applyPlace(request.place, action: "create", to: &draft) { return outcome }
            let made = try await store.create(draft)
            return ReminderFlowOutcome(text: ReminderAnswer.created(made), trace: trace("create", made),
                                       ref: ReminderRef(made), changed: true)
        } catch {
            return failure(error, action: "create")
        }
    }

    private func change(_ request: ReminderRequest) async -> ReminderFlowOutcome {
        do {
            let list = request.list
            let target = try await target(request, requiresTitle: false, list: list,
                                          searchesAllLists: true)
            var draft = ReminderDraft(title: request.title.isEmpty ? nil : request.title,
                                      list: list,
                                      notes: request.notes, due: request.due, allDay: request.allDay,
                                      repeatRule: request.repeatRule, priority: request.priority,
                                      place: request.place)
            if let outcome = await applyPlace(request.place, action: "update", to: &draft) { return outcome }
            let made = try await store.update(target.id, with: draft)
            return ReminderFlowOutcome(text: ReminderAnswer.updated(made), trace: trace("update", made),
                                       ref: ReminderRef(made), changed: true)
        } catch {
            return failure(error, action: "update")
        }
    }

    private func complete(_ request: ReminderRequest) async -> ReminderFlowOutcome {
        await onNamedTarget(request, action: "complete") { target in
            let made = try await store.complete(target.id, at: Date())
            return ReminderFlowOutcome(text: ReminderAnswer.completed(made), trace: trace("complete", made),
                                       ref: ReminderRef(made), changed: true)
        }
    }

    private func delete(_ request: ReminderRequest) async -> ReminderFlowOutcome {
        await onNamedTarget(request, action: "delete") { target in
            try await store.delete(target.id)
            return ReminderFlowOutcome(text: ReminderAnswer.deleted(target),
                                       trace: "aktion=delete liste=\(target.list) "
                                           + "titel=\(TextLine.oneLine(target.title, limit: 40))",
                                       ref: nil, changed: true)
        }
    }

    private func onNamedTarget(_ request: ReminderRequest, action: String,
                               _ apply: (StoredReminder) async throws -> ReminderFlowOutcome) async
        -> ReminderFlowOutcome {
        do {
            let target = try await target(request, requiresTitle: true, list: request.list)
            return try await apply(target)
        } catch {
            return failure(error, action: action)
        }
    }

    private func target(_ request: ReminderRequest, requiresTitle: Bool, list: String?,
                        searchesAllLists: Bool = false) async throws -> StoredReminder {
        let open = try await store.open()
        if let list {
            if let found = match(request, in: open.filter { $0.list == list },
                                 requiresTitle: requiresTitle) {
                return found
            }
            guard searchesAllLists else { throw APIError(message: ReminderAnswer.notFound(request)) }
        }
        guard let found = match(request, in: open, requiresTitle: requiresTitle) else {
            throw APIError(message: ReminderAnswer.notFound(request))
        }
        return found
    }

    private func match(_ request: ReminderRequest, in pool: [StoredReminder],
                       requiresTitle: Bool) -> StoredReminder? {
        let candidates = pool.map { reminder in
            ReminderMatch(title: reminder.title, location: reminder.place ?? "",
                          notes: reminder.notes, due: reminder.due)
        }
        guard let index = ReminderMatching.bestIndex(in: candidates, query: request.find,
                                                     now: Date(), requiresTitle: requiresTitle) else {
            return nil
        }
        return pool[index]
    }

    private func matchedList(_ requested: String?) async -> String? {
        guard let requested else { return nil }
        let outcome = ReminderListChoice.resolve(requested: requested, available: await store.lists(),
                                                 deviceDefault: await store.defaultListTitle(),
                                                 silent: .keepCurrent)
        guard case .title(let name) = outcome else { return nil }
        return name
    }

    private func creationList(_ requested: String?) async throws -> String? {
        let available = await store.lists()
        guard !available.isEmpty else { return nil }
        switch ReminderListChoice.resolve(requested: requested, available: available,
                                          deviceDefault: await store.defaultListTitle(),
                                          silent: .deviceDefault) {
        case .title(let name): return name
        case .keep: return available.first
        case .unmatched(let asked):
            throw APIError(message: L.fmt2("rem_list_missing", asked, available.joined(separator: ", ")))
        }
    }

    private enum PlaceLookup {
        case found(GeoPoint)
        case missing(ReminderFlowOutcome)
    }

    private func applyPlace(_ place: ReminderPlace?, action: String,
                            to draft: inout ReminderDraft) async -> ReminderFlowOutcome? {
        guard let place else { return nil }
        switch await placeLookup(place, action: action) {
        case .missing(let outcome): return outcome
        case .found(let point): draft.coordinates = point; return nil
        }
    }

    private func placeLookup(_ place: ReminderPlace, action: String) async -> PlaceLookup {
        guard let point = await places.locate(place.name) else {
            return .missing(ReminderFlowOutcome(text: L.fmt("rem_place_missing", place.name),
                                                trace: "aktion=\(action) ort=\(place.name) gefunden=false",
                                                ref: nil))
        }
        return .found(point)
    }

    private func trace(_ action: String, _ reminder: StoredReminder) -> String {
        "aktion=\(action) liste=\(reminder.list) titel=\(TextLine.oneLine(reminder.title, limit: 40)) "
            + "ort=\(reminder.place ?? "-") wiederholung=\(reminder.repeatRule?.frequency.rawValue ?? "-")"
    }

    private func failure(_ error: Error, action: String) -> ReminderFlowOutcome {
        let message = (error as? APIError)?.message ?? L.t("rem_failed")
        return ReminderFlowOutcome(text: message,
                                   trace: "aktion=\(action) fehler="
                                       + TextLine.oneLine(error.localizedDescription, limit: 120),
                                   ref: nil)
    }
}
