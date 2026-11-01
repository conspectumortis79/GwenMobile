import GwenMobileKit
import Foundation
import SwiftUI
import UserNotifications

#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
import AlarmKit
#endif

enum TimerSettingResult: Equatable, Sendable {
    case set(duration: TimeInterval, way: String)
    case denied
    case unavailable
    case failed(String)

    var trace: String {
        switch self {
        case .set(let duration, let way):
            let seconds = Int(exactly: duration.rounded()) ?? Int.max
            return "gestellt=\(seconds)s weg=\(way)"
        case .denied: return "berechtigung=fehlt"
        case .unavailable: return "nicht_verfuegbar"
        case .failed(let detail): return "fehler=" + detail
        }
    }

    var isSet: Bool {
        guard case .set = self else { return false }
        return true
    }
}

@MainActor
protocol TimerSetting {
    func set(_ request: TimerRequest) async -> TimerSettingResult
}

@MainActor
struct StubTimerSetter: TimerSetting {
    func set(_ request: TimerRequest) async -> TimerSettingResult { .unavailable }
}

@MainActor
enum TimerSetterPort {
    nonisolated(unsafe) static var current: any TimerSetting = StubTimerSetter()
}
