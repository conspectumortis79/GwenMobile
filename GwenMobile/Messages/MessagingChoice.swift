import Foundation

struct MessagingCapability: Equatable, Sendable {
    let core: DirectCapability

    var entitled: Bool { core.entitled }
    var direct: Bool { core.isReady }

    init(entitled: Bool, carrierAvailable: Bool) {
        core = DirectCapability(entitled: entitled, available: carrierAvailable)
    }

    init(_ core: DirectCapability) {
        self.core = core
    }

    #if DEBUG
    var trace: String { core.trace(readyLabel: "direkt") }
    #endif
}

enum MessagingChoice {
    static let infoKey = "GwenCarrierMessaging"

    static func capability(bundle: Bundle = .main, carrierAvailable: Bool) -> MessagingCapability {
        MessagingCapability(DirectCapability.of(infoKey: infoKey, in: bundle, available: carrierAvailable))
    }

    @MainActor static func current(bundle: Bundle = .main) -> MessagingCapability {
        capability(bundle: bundle, carrierAvailable: MessageSenderPort.carrier() != nil)
    }

    @MainActor static func sender(for capability: MessagingCapability,
                                  carrier: @MainActor () -> (any MessageSending)? = MessageSenderPort.carrier,
                                  compose: @MainActor () -> any MessageSending = { MessageSenderPort.compose() })
        -> any MessageSending {
        DirectChannel.select(ready: capability.direct, direct: carrier, fallback: compose(),
                             combined: FallbackMessageSender.init)
    }
}
