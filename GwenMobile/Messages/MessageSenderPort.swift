import GwenMobileKit
import Foundation

@MainActor
struct StubMessageSender: MessageSending {
    var way: String { "stub" }

    func send(_ text: String, to number: DialNumber) async -> MessageSendResult {
        .unavailable
    }
}

@MainActor
enum MessageSenderPort {
    nonisolated(unsafe) static var carrier: @MainActor () -> (any MessageSending)? = { nil }
    nonisolated(unsafe) static var compose: @MainActor () -> any MessageSending = { StubMessageSender() }
}
