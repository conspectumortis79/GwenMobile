import Foundation

@MainActor
protocol ReminderPlaceLooking {
    func locate(_ name: String) async -> GeoPoint?
}

enum ReminderPlaceRadius {
    static let narrow: Double = 150
}

@MainActor
final class StubReminderPlaceLookup: ReminderPlaceLooking {
    func locate(_ name: String) async -> GeoPoint? { nil }
}

@MainActor
enum ReminderPlacePort {
    nonisolated(unsafe) static var current: any ReminderPlaceLooking = StubReminderPlaceLookup()
}

@MainActor
struct ReminderPlaceLookupChain: ReminderPlaceLooking {
    let first: any ReminderPlaceLooking
    let second: any ReminderPlaceLooking

    func locate(_ name: String) async -> GeoPoint? {
        if let hit = await first.locate(name) { return hit }
        return await second.locate(name)
    }
}
