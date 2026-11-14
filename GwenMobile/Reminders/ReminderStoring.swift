import GwenMobileKit
import Foundation

struct GeoPoint: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var radius: Double
}

struct ReminderDraft: Equatable, Sendable {
    var title: String?
    var list: String?
    var notes: String?
    var due: Date?
    var allDay: Bool = false
    var repeatRule: ReminderRepeat?
    var priority: ReminderPriority?
    var place: ReminderPlace?
    var coordinates: GeoPoint?
}

struct StoredReminder: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var list: String
    var notes: String = ""
    var due: Date?
    var allDay = false
    var isCompleted = false
    var priority: ReminderPriority?
    var place: String?
    var proximity: ReminderPlace.Proximity?
    var repeatRule: ReminderRepeat?

    var placeDescription: String? {
        guard let place else { return nil }
        return (proximity == .leave ? L.t("rem_leave") : L.t("rem_arrive")) + " " + place
    }
}

@MainActor
protocol ReminderStoring {
    func hasAccess() async -> Bool
    func lists() async -> [String]
    func defaultListTitle() async -> String?
    func open() async throws -> [StoredReminder]
    func create(_ draft: ReminderDraft) async throws -> StoredReminder
    func update(_ id: String, with draft: ReminderDraft) async throws -> StoredReminder
    func complete(_ id: String, at date: Date) async throws -> StoredReminder
    func delete(_ id: String) async throws
}
