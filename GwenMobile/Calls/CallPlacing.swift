import GwenMobileKit
import Foundation

enum CallStart: String, Equatable, Sendable {
    case dialing
    case confirming
    case failed
}

@MainActor
protocol CallPlacing {
    var way: String { get }
    func place(_ number: DialNumber) async -> CallStart
}

@MainActor
protocol URLOpening {
    func open(_ url: URL) async -> Bool
}

@MainActor
struct PhoneLinkDialer: CallPlacing {
    private let opener: any URLOpening

    init(opener: any URLOpening = SystemURLOpener()) {
        self.opener = opener
    }

    var way: String { "telefonlink" }

    func place(_ number: DialNumber) async -> CallStart {
        guard let url = number.telURL else { return .failed }
        return await opener.open(url) ? .confirming : .failed
    }
}

@MainActor
struct FallbackDialer: CallPlacing {
    private let first: any CallPlacing
    private let then: any CallPlacing

    init(first: any CallPlacing, then: any CallPlacing) {
        self.first = first
        self.then = then
    }

    var way: String { "\(first.way)>\(then.way)" }

    func place(_ number: DialNumber) async -> CallStart {
        let started = await first.place(number)
        guard started == .failed else { return started }
        flowMark("ANRUF weg=\(first.way) fehlgeschlagen ersatz=\(then.way)")
        return await then.place(number)
    }
}
