@testable import GwenMobileFeatureCore
import GwenMobileKit
#if canImport(LiveCommunicationKit) && !targetEnvironment(macCatalyst)
import Foundation
import LiveCommunicationKit

@MainActor
struct CellularDialer: CallPlacing {
    var way: String { "mobilfunk" }

    func place(_ number: DialNumber) async -> CallStart {
        let action = StartCellularConversationAction(Handle(type: .phoneNumber, value: number.digits))
        do {
            try await TelephonyConversationManager.sharedInstance.startCellularConversation(action)
            return .dialing
        } catch {
            flowMark("ANRUF mobilfunk fehler=" + TextLine.oneLine(String(describing: error), limit: 160))
            return .failed
        }
    }
}

enum CellularDialerFactory {
    @MainActor static func make() -> (any CallPlacing)? {
        CellularDialer()
    }
}
#else
enum CellularDialerFactory {
    @MainActor static func make() -> (any CallPlacing)? { nil }
}
#endif
