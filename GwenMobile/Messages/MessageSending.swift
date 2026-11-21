import GwenMobileKit

enum MessageSendResult: Equatable, Sendable {
    case sent(direct: Bool)
    case cancelled
    case unavailable
    case needsForeground
    case failed(String)

    var trace: String {
        switch self {
        case .sent(let direct): return direct ? "direkt_gesendet" : "formular_gesendet"
        case .cancelled: return "abgebrochen"
        case .unavailable: return "nicht_moeglich"
        case .needsForeground: return "braucht_vordergrund"
        case .failed(let detail): return "fehler:" + detail
        }
    }

    var isSent: Bool {
        guard case .sent = self else { return false }
        return true
    }
}

@MainActor
protocol MessageSending {
    var way: String { get }
    func send(_ text: String, to number: DialNumber) async -> MessageSendResult
}

@MainActor
struct FallbackMessageSender: MessageSending {
    private let first: any MessageSending
    private let then: any MessageSending

    init(first: any MessageSending, then: any MessageSending) {
        self.first = first
        self.then = then
    }

    var way: String { "\(first.way)>\(then.way)" }

    func send(_ text: String, to number: DialNumber) async -> MessageSendResult {
        let result = await first.send(text, to: number)
        guard result == .unavailable else { return result }
        flowMark("NACHRICHT weg=\(first.way) nicht_moeglich ersatz=\(then.way)")
        return await then.send(text, to: number)
    }
}
