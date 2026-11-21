import GwenMobileKit
import Foundation

enum ReminderTitle {
    static func merged(_ titles: [String]) -> String {
        titles
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
