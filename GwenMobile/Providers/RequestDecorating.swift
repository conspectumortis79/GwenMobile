import GwenMobileKit
import Foundation

protocol RequestDecorating: Sendable {
    func decorate(_ request: inout URLRequest)
}

struct NoRequestDecoration: RequestDecorating {
    func decorate(_ request: inout URLRequest) {}
}

extension HTTP {
    static let decorator = LockedValue<any RequestDecorating>(NoRequestDecoration())

    static func prepare(_ req: inout URLRequest, key: String) {
        authorize(&req, key: key)
        decorator.current.decorate(&req)
    }
}
