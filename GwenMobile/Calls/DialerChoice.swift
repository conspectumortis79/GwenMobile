import Foundation

struct DialerCapability: Equatable, Sendable {
    let core: DirectCapability

    var entitled: Bool { core.entitled }
    var handsFree: Bool { core.isReady }

    init(entitled: Bool, cellularAvailable: Bool) {
        core = DirectCapability(entitled: entitled, available: cellularAvailable)
    }

    init(_ core: DirectCapability) {
        self.core = core
    }

    #if DEBUG
    var trace: String { core.trace(readyLabel: "freihaendig") }
    #endif
}

@MainActor
enum DialerPort {
    nonisolated(unsafe) static var cellular: @MainActor () -> (any CallPlacing)? = { nil }
}

enum DialerChoice {
    static let infoKey = "GwenDefaultDialer"

    static func capability(bundle: Bundle = .main, cellularAvailable: Bool) -> DialerCapability {
        DialerCapability(DirectCapability.of(infoKey: infoKey, in: bundle, available: cellularAvailable))
    }

    @MainActor static func current(bundle: Bundle = .main) -> DialerCapability {
        capability(bundle: bundle, cellularAvailable: DialerPort.cellular() != nil)
    }

    @MainActor static func dialer(for capability: DialerCapability,
                                  cellular: @MainActor () -> (any CallPlacing)? = DialerPort.cellular,
                                  link: any CallPlacing = PhoneLinkDialer()) -> any CallPlacing {
        DirectChannel.select(ready: capability.handsFree, direct: cellular, fallback: link,
                             combined: FallbackDialer.init)
    }
}
