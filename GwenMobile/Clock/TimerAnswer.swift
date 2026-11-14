import GwenMobileKit
import Foundation

enum TimerAnswer {
    static func title(_ request: TimerRequest) -> String {
        let named = request.title?.trimmed ?? ""
        return named.isEmpty ? L.t("timer_default_title") : named
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(1, Int(exactly: seconds.rounded()) ?? Int.max)
        let minutes = total / 60
        let rest = total % 60
        var parts: [String] = []
        if minutes > 0 {
            parts.append(L.n(minutes == 1 ? "timer_minute" : "timer_minutes", minutes))
        }
        if rest > 0 {
            parts.append(L.n(rest == 1 ? "timer_second" : "timer_seconds", rest))
        }
        return parts.joined(separator: " ")
    }

    static func result(_ result: TimerSettingResult, request: TimerRequest) -> String {
        switch result {
        case .set(let duration, _):
            let named = request.title?.trimmed ?? ""
            if named.isEmpty {
                return L.fmt("timer_set_plain", Self.duration(duration))
            }
            return L.fmt2("timer_set", named, Self.duration(duration))
        case .denied:
            return L.t("timer_denied")
        case .unavailable:
            return L.t("timer_unavailable")
        case .failed:
            return L.t("timer_failed")
        }
    }
}
