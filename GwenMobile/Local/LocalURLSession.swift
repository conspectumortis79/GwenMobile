import Foundation

enum LocalURLSession {
    static func ephemeral(requestTimeout: TimeInterval, resourceTimeout: TimeInterval,
                          connectionsPerHost: Int) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpMaximumConnectionsPerHost = connectionsPerHost
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}
