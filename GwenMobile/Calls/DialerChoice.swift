import GwenMobileKit
import Foundation

struct DialerCapability: Equatable, Sendable {
    let entitled: Bool
    let cellularAvailable: Bool

    var handsFree: Bool { entitled && cellularAvailable }

    #if DEBUG
    var trace: String { "berechtigt=\(entitled) mobilfunk_api=\(cellularAvailable) freihaendig=\(handsFree)" }
    #endif
}

@MainActor
enum DialerPort {
    nonisolated(unsafe) static var cellular: @MainActor () -> (any CallPlacing)? = { nil }
}

enum DialerChoice {
    static let infoKey = "GwenDefaultDialer"

    static func capability(bundle: Bundle = .main, cellularAvailable: Bool) -> DialerCapability {
        DialerCapability(entitled: BuildFlag.isOn(infoKey, in: bundle), cellularAvailable: cellularAvailable)
    }

    @MainActor static func current(bundle: Bundle = .main) -> DialerCapability {
        capability(bundle: bundle, cellularAvailable: DialerPort.cellular() != nil)
    }

    @MainActor static func dialer(for capability: DialerCapability,
                                  cellular: @MainActor () -> (any CallPlacing)? = DialerPort.cellular,
                                  link: any CallPlacing = PhoneLinkDialer()) -> any CallPlacing {
        guard capability.handsFree, let cellular = cellular() else { return link }
        return FallbackDialer(first: cellular, then: link)
    }
}
