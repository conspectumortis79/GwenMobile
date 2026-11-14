import GwenMobileKit
import Foundation

enum ListenSwitch {
    enum Outcome: Equatable {
        case openSettings
        case turned(on: Bool)
    }

    static func tap(isOn: Bool, configured: Bool) -> Outcome {
        if isOn { return .turned(on: false) }
        return configured ? .turned(on: true) : .openSettings
    }

    static func noticeKey(on: Bool) -> String {
        on ? "listen_notice_on" : "listen_notice_off"
    }
}
