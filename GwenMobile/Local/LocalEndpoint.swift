import GwenMobileKit
import Foundation

enum LocalEndpoint {
    static let host = "gwen.local"
    static let baseURL = "http://gwen.local/v1"

    static func isLocal(_ request: URLRequest) -> Bool {
        request.url?.host == host
    }

    static func isLocal(_ url: URL?) -> Bool {
        url?.host == host
    }

    static func path(_ request: URLRequest) -> String {
        request.url?.path ?? ""
    }
}
