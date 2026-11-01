import GwenMobileKit
import Foundation

enum ReminderListChoice {
    static func resolve(requested: String?, available: [String], deviceDefault: String?,
                        silent: CalendarChoice.Silent = .deviceDefault) -> CalendarChoice.Outcome {
        CalendarChoice.resolve(requested: requested, available: available,
                              deviceDefault: deviceDefault, silent: silent)
    }
}
