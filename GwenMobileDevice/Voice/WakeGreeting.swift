@testable import GwenMobileFeatureCore
import Foundation

enum WakeGreeting {
    static let keys = ["wake_greeting_1", "wake_greeting_2", "wake_greeting_3"]

    static func random() -> String {
        L.t(keys[Int.random(in: 0..<keys.count)])
    }
}
