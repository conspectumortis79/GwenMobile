@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import MessageUI
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

@MainActor
private final class MessageHost: UIViewController {
    private(set) var sheets = 0

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool,
                          completion: (() -> Void)? = nil) {
        sheets += 1
        completion?()
    }
}

@MainActor
final class MessagesLogicGapTests: GwenTestCase {
    func testTheComposeSenderGuards() async {
        let host = MessageHost()
        _ = ComposeMessageSender.result(of: .cancelled)
        _ = ComposeMessageSender.result(of: .failed)
        let sender = ComposeMessageSender(canSend: { false }, isActive: { true }, host: { host })
        _ = await sender.send("x", to: DialNumber("030123456")!)
        let background = ComposeMessageSender(canSend: { true }, isActive: { false }, host: { host })
        _ = await background.send("x", to: DialNumber("030123456")!)
        let noHost = ComposeMessageSender(canSend: { true }, isActive: { true }, host: { nil })
        _ = await noHost.send("x", to: DialNumber("030123456")!)
        XCTAssertEqual(sender.way, "nachrichtenformular")
    }

    #if !targetEnvironment(macCatalyst)
    func testSmokeTheCarrierSenderWithoutEntitlement() async {
        _ = await CarrierMessageSender().send("Hallo", to: DialNumber("030123")!)
    }
    #endif

    func testSmokeTheMessageDeskRestores() {
        let desk = MessageDesk(directory: FixtureContacts(), sender: ProbeMessenger(),
                               reviewer: ProbeMessenger())
        desk.stand(in: ProbeMessenger(), directory: FixtureContacts())
        desk.restore()
        desk.restore()
        _ = desk.runner()
    }
}
