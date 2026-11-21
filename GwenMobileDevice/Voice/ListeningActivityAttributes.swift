import Foundation
import SwiftUI
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

enum ListeningActivityPalette {
    static let rainbow = [
        Color(red: 1.00, green: 0.26, blue: 0.54),
        Color(red: 1.00, green: 0.58, blue: 0.16),
        Color(red: 1.00, green: 0.90, blue: 0.28),
        Color(red: 0.36, green: 1.00, blue: 0.55),
        Color(red: 0.22, green: 0.86, blue: 1.00),
        Color(red: 0.34, green: 0.44, blue: 1.00),
        Color(red: 0.74, green: 0.30, blue: 1.00),
        Color(red: 1.00, green: 0.26, blue: 0.54)
    ]

    static var rainbowGradient: AngularGradient {
        AngularGradient(gradient: Gradient(colors: rainbow), center: .center)
    }
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
struct ListeningActivityAttributes: ActivityAttributes, Sendable {
    enum Mode: String, Codable, Hashable, Sendable {
        case listen
        case conversation
    }

    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case armed
            case recording
            case processing
        }

        var phase: Phase
        var title: String
        var startedAt: Date
    }

    var mode: Mode
}
#endif
