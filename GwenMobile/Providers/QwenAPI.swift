import GwenMobileKit
import Foundation

enum QwenAPI {
    struct CalendarPlan: Decodable, Equatable {
        enum Action: String, Decodable, Equatable { case create, update, delete, none }
        var action: Action
        var title: String?
        var start: String?
        var end: String?
        var location: String?
        var notes: String?
        var find: String?
        var alerts: [Int]?
        var calendar: String?
    }

}

struct ModelsPayload: Decodable {
    struct ModelEntry: Decodable { var id: String }
    var data: [ModelEntry]
}
