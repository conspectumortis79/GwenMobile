import GwenMobileKit
import Foundation

struct ProbeResponse: Sendable {
    let status: Int
    let body: Data

    var succeeded: Bool { status < 400 }
    var rejectedByProvider: Bool { status >= 400 && status < 500 }
}

enum HTTP {
    static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APITimeout.streamIdle
        config.timeoutIntervalForResource = APITimeout.streamResource
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        if let protocolClasses {
            config.protocolClasses = protocolClasses
        }
        return URLSession(configuration: config)
    }

    nonisolated(unsafe) static var localResponder: (@Sendable (URLRequest) async -> (Data, URLResponse)?)?

    private static let sessionBox = LockedValue(makeSession())

    static var session: URLSession {
        get { sessionBox.current }
        set { sessionBox.set(newValue) }
    }

    static func root(_ baseURL: String) -> String {
        var root = baseURL.trimmed
        while root.hasSuffix("/") { root.removeLast() }
        return root
    }

    static func endpoint(_ baseURL: String, _ path: String) -> URL? {
        let root = root(baseURL)
        guard !root.isEmpty, let url = URL(string: root + path), url.host != nil else { return nil }
        return url
    }

    static func requiredURL(_ baseURL: String, _ path: String) throws -> URL {
        guard let url = endpoint(baseURL, path) else { throw APIError(message: L.t("bad_url")) }
        return url
    }

    static func chatCompletionsURL(_ baseURL: String) throws -> URL {
        try requiredURL(baseURL, APIEndpoint.chatCompletions)
    }

    static func jsonPOST(url: URL, key: String, body: [String: Any],
                         timeout: TimeInterval, accept: String? = nil) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accept { req.setValue(accept, forHTTPHeaderField: "Accept") }
        prepare(&req, key: key)
        req.timeoutInterval = timeout
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func authorizedGET(url: URL, key: String, timeout: TimeInterval) -> URLRequest {
        var req = URLRequest(url: url)
        prepare(&req, key: key)
        req.timeoutInterval = timeout
        return req
    }

    static func authorizedGET(baseURL: String, path: String, key: String,
                              timeout: TimeInterval) throws -> URLRequest {
        authorizedGET(url: try requiredURL(baseURL, path), key: key, timeout: timeout)
    }

    static func authorize(_ req: inout URLRequest, key: String) {
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }

    static func ensureAPISuccess(_ response: URLResponse, data: Data) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code >= 400 else { return }
        throw APIError(message: APIErrorParser.message(from: data, status: code), status: code)
    }

    static func ensureSuccess(_ response: URLResponse) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code >= 400 else { return }
        throw APIError(message: "HTTP \(code)")
    }

    static let connectionRetryCodes: Set<URLError.Code> = [
        .secureConnectionFailed, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed,
    ]
    static let unreachedConnectionCodes: Set<URLError.Code> = [
        .secureConnectionFailed, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed,
    ]
    static let connectionRetryBackoff = Duration.milliseconds(1200)

    static func isConnectionReset(_ error: URLError) -> Bool {
        connectionRetryCodes.contains(error.code)
    }

    static func isIdempotent(_ request: URLRequest) -> Bool {
        guard let method = request.httpMethod?.uppercased() else { return true }
        return method == "GET" || method == "HEAD"
    }

    static func canRetry(_ error: URLError, request: URLRequest) -> Bool {
        guard connectionRetryCodes.contains(error.code) else { return false }
        if isIdempotent(request) { return true }
        return unreachedConnectionCodes.contains(error.code)
    }

    static func data(_ req: URLRequest) async throws -> (Data, URLResponse) {
        if let responder = localResponder, let answer = await responder(req) {
            return answer
        }
        do {
            return try await session.data(for: req)
        } catch let error as URLError where canRetry(error, request: req) {
            try await Task.sleep(for: connectionRetryBackoff)
            return try await session.data(for: req)
        }
    }

    static func jsonData(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await data(req)
        try ensureAPISuccess(response, data: data)
        return data
    }

    static func probeResponse(_ req: URLRequest) async -> ProbeResponse? {
        guard let (body, response) = try? await data(req),
              let http = response as? HTTPURLResponse else { return nil }
        return ProbeResponse(status: http.statusCode, body: body)
    }
}
