import GwenMobileKit
import Foundation

enum SourceGuard {
    enum Risk: String, Sendable {
        case clear
        case caution
        case blocked
    }

    enum Reason: String, Sendable {
        case reported
        case unencrypted
        case punycode
        case ipAddress = "ip_address"
        case unsafeAddress = "unsafe_address"

        nonisolated var promptText: String {
            PromptLibrary.field("web_source_reasons", rawValue)
        }
    }

    struct Verdict: Equatable, Sendable {
        var risk: Risk = .clear
        var reasons: [Reason] = []

        var isBlocked: Bool { risk == .blocked }

        func merging(_ other: Verdict) -> Verdict {
            var merged = reasons
            for reason in other.reasons where !merged.contains(reason) { merged.append(reason) }
            return Verdict(risk: Self.worst(risk, other.risk), reasons: merged)
        }

        private static func worst(_ first: Risk, _ second: Risk) -> Risk {
            switch (first, second) {
            case (.blocked, _), (_, .blocked): return .blocked
            case (.caution, _), (_, .caution): return .caution
            default: return .clear
            }
        }
    }

    static func assess(_ url: URL?, reported: Bool) -> Verdict {
        guard let url else { return Verdict(risk: .caution, reasons: [.unsafeAddress]) }
        var verdict = Verdict()
        if url.user != nil || url.password != nil {
            verdict = verdict.merging(Verdict(risk: .blocked, reasons: [.unsafeAddress]))
        }
        if reported {
            verdict = verdict.merging(Verdict(risk: .blocked, reasons: [.reported]))
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return verdict.merging(Verdict(risk: .caution, reasons: [.unsafeAddress]))
        }
        if URLSafety.isLocalOrPrivateHost(host) {
            let reasons: [Reason] = URLSafety.isIPAddress(host) ? [.ipAddress, .unsafeAddress] : [.unsafeAddress]
            verdict = verdict.merging(Verdict(risk: .blocked, reasons: reasons))
        } else if URLSafety.isIPAddress(host) {
            verdict = verdict.merging(Verdict(risk: .caution, reasons: [.ipAddress]))
        }
        if host.split(separator: ".").contains(where: { $0.hasPrefix("xn--") }) {
            verdict = verdict.merging(Verdict(risk: .caution, reasons: [.punycode]))
        }
        if url.scheme?.lowercased() != "https" {
            verdict = verdict.merging(Verdict(risk: .caution, reasons: [.unencrypted]))
        }
        return verdict
    }

}
