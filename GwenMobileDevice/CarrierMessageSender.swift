@testable import GwenMobileFeatureCore
import GwenMobileKit
#if canImport(TelephonyMessagingKit) && !targetEnvironment(macCatalyst)
import Foundation
import TelephonyMessagingKit

@MainActor
struct CarrierMessageSender: MessageSending {
    var way: String { "mobilfunk_sms" }

    func send(_ text: String, to number: DialNumber) async -> MessageSendResult {
        let session = TelephonyMessagingSession.shared
        guard session.isConfiguredForCarrierMessaging else { return .unavailable }
        do {
            guard let service = try session.cellularServices.first else { return .unavailable }
            let message = SMSMessage(cellularServiceID: service.id, handle: SMSHandle(phoneNumber: number.digits),
                                     messageID: SMSMessageID(rawValue: UInt32.random(in: 1...UInt32.max)),
                                     content: SMSContent(body: text))
            try await session.smsService.sendMessage(message)
            return .sent(direct: true)
        } catch {
            flowMark("NACHRICHT mobilfunk fehler=" + TextLine.oneLine(String(describing: error), limit: 160))
            return .failed(TextLine.oneLine(error.localizedDescription, limit: 120))
        }
    }
}

enum CarrierMessageSenderFactory {
    @MainActor static func make() -> (any MessageSending)? {
        CarrierMessageSender()
    }
}
#else
enum CarrierMessageSenderFactory {
    @MainActor static func make() -> (any MessageSending)? { nil }
}
#endif
