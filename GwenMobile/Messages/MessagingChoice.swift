import GwenMobileKit
import Foundation

struct MessagingCapability: Equatable, Sendable {
    let entitled: Bool
    let carrierAvailable: Bool

    var direct: Bool { entitled && carrierAvailable }

    #if DEBUG
    var trace: String { "berechtigt=\(entitled) mobilfunk_api=\(carrierAvailable) direkt=\(direct)" }
    #endif
}

enum MessagingChoice {
    static let infoKey = "GwenCarrierMessaging"

    static func capability(bundle: Bundle = .main, carrierAvailable: Bool) -> MessagingCapability {
        MessagingCapability(entitled: BuildFlag.isOn(infoKey, in: bundle), carrierAvailable: carrierAvailable)
    }

    @MainActor static func current(bundle: Bundle = .main) -> MessagingCapability {
        capability(bundle: bundle, carrierAvailable: MessageSenderPort.carrier() != nil)
    }

    @MainActor static func sender(for capability: MessagingCapability,
                                  carrier: @MainActor () -> (any MessageSending)? = MessageSenderPort.carrier,
                                  compose: @MainActor () -> any MessageSending = { MessageSenderPort.compose() })
        -> any MessageSending {
        let form = compose()
        guard capability.direct, let carrier = carrier() else { return form }
        return FallbackMessageSender(first: carrier, then: form)
    }
}
