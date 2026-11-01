@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class CallPlacingTests: GwenTestCase {
    private struct StubOpener: URLOpening {
        let answer: Bool
        func open(_ url: URL) async -> Bool { answer }
    }

    private final class CountingDialer: CallPlacing {
        let way = "zahler"
        private(set) var calls = 0
        private let answer: CallStart

        init(answer: CallStart) {
            self.answer = answer
        }

        func place(_ number: DialNumber) async -> CallStart {
            calls += 1
            return answer
        }
    }

    func testThePhoneLinkDialerNamesItsWayAndConfirms() async throws {
        let dialer = PhoneLinkDialer(opener: StubOpener(answer: true))
        XCTAssertEqual(dialer.way, "telefonlink")
        let number = try XCTUnwrap(DialNumber("+49 30 1234567"))
        let start = await dialer.place(number)
        XCTAssertEqual(start, .confirming)
    }

    func testTheFallbackDialerOnlyTriesTheSecondAfterAFailure() async throws {
        let first = CountingDialer(answer: .failed)
        let second = CountingDialer(answer: .dialing)
        let dialer = FallbackDialer(first: first, then: second)
        let number = try XCTUnwrap(DialNumber("+49 30 1234567"))
        let start = await dialer.place(number)
        XCTAssertEqual(start, .dialing)
        XCTAssertEqual(first.calls, 1)
        XCTAssertEqual(second.calls, 1)
        XCTAssertEqual(dialer.way, "zahler>zahler")
    }

    func testTheDialerChoiceExplainsItselfAndFallsBackToTheLink() {
        let capability = DialerCapability(entitled: true, cellularAvailable: false)
        XCTAssertTrue(capability.trace.contains("freihaendig=false"), capability.trace)
        let dialer = DialerChoice.dialer(for: capability, cellular: { nil },
                                         link: PhoneLinkDialer(opener: StubOpener(answer: true)))
        XCTAssertEqual(dialer.way, "telefonlink")
    }

    func testTheDefaultCellularLookupIsAlwaysAnswered() {
        let capability = DialerCapability(entitled: true, cellularAvailable: true)
        XCTAssertFalse(DialerChoice.dialer(for: capability).way.isEmpty)
    }

    func testTheCallDeskBuildsItsRunner() {
        XCTAssertNotNil(CallDesk().runner())
    }
}
