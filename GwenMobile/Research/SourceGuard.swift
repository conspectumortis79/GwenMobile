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
            Verdict(risk: Self.worst(risk, other.risk), reasons: reasons + other.reasons)
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
        if isAddress(host) {
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

    private static func isAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber) && (Int(part).map { $0 <= 255 } ?? false)
        }
    }
}
