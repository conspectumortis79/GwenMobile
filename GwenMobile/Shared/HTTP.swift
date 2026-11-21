import GwenMobileKit
import Foundation

struct ProbeResponse: Sendable {
    static let inconclusiveStatuses: Set<Int> = [401, 402, 403, 404, 408, 429]

    let status: Int
    let body: Data

    var succeeded: Bool { status < 400 }
    var rejectedByProvider: Bool { status >= 400 && status < 500 }
    var isConclusive: Bool { status < 500 && !Self.inconclusiveStatuses.contains(status) }
}

final class HTTPRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let allowLocal: Bool
    private let secureOnly: Bool
    private var blockedURL: URL?

    var blocked: URL? {
        lock.lock()
        defer { lock.unlock() }
        return blockedURL
    }

    init(blockedURL: URL? = nil, allowLocal: Bool = false, secureOnly: Bool = false) {
        self.blockedURL = blockedURL
        self.allowLocal = allowLocal
        self.secureOnly = secureOnly
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let target = request.url,
              let scheme = target.scheme?.lowercased(),
              !(response.url?.scheme?.lowercased() == "https" && scheme != "https"),
              secureOnly ? scheme == "https" : (scheme == "http" || scheme == "https"),
              allowLocal || !URLSafety.isLocalOrPrivateResolvedHost(target.host ?? "") else {
            lock.lock()
            blockedURL = request.url
            lock.unlock()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
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

    static func pathSegment(_ raw: String) throws -> String {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty, trimmed != ".", trimmed != "..",
              !trimmed.contains("/"), !trimmed.contains("\\"),
              !trimmed.contains("?"), !trimmed.contains("#"),
              trimmed.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }),
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else {
            throw APIError(message: L.t("bad_url"))
        }
        return encoded
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

    static func statusCode(of response: URLResponse?) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? -1
    }

    static func isSuccessStatus(_ code: Int) -> Bool {
        (200..<300).contains(code)
    }

    static func ensureAPISuccess(_ response: URLResponse, data: Data) throws {
        let code = statusCode(of: response)
        guard !isSuccessStatus(code) else { return }
        throw APIError(message: APIErrorParser.message(from: data, status: code),
                       status: code >= 0 ? code : nil)
    }

    static func ensureSuccess(_ response: URLResponse) throws {
        let code = statusCode(of: response)
        guard !isSuccessStatus(code) else { return }
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

    static func data(_ req: URLRequest, allowLocalRedirects: Bool = false,
                     secureOnly: Bool = false) async throws
        -> (Data, URLResponse) {
        if let responder = localResponder, let answer = await responder(req) {
            return answer
        }
        do {
            return try await guardedData(req, allowLocalRedirects: allowLocalRedirects,
                                         secureOnly: secureOnly)
        } catch let error as URLError where canRetry(error, request: req) {
            try await Task.sleep(for: connectionRetryBackoff)
            return try await guardedData(req, allowLocalRedirects: allowLocalRedirects,
                                         secureOnly: secureOnly)
        }
    }

    static func streamData(_ req: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        let redirects = HTTPRedirectGuard()
        do {
            let answer = try await session.bytes(for: req, delegate: redirects)
            return try validated(answer, redirects: redirects)
        } catch {
            if let blocked = redirects.blocked {
                throw blockedRedirect(blocked)
            }
            throw error
        }
    }

    private static func guardedData(_ req: URLRequest,
                                    allowLocalRedirects: Bool,
                                    secureOnly: Bool = false) async throws -> (Data, URLResponse) {
        let redirects = HTTPRedirectGuard(allowLocal: allowLocalRedirects, secureOnly: secureOnly)
        let answer: (Data, URLResponse)
        do {
            answer = try await session.data(for: req, delegate: redirects)
        } catch {
            if let blocked = redirects.blocked {
                throw blockedRedirect(blocked)
            }
            throw error
        }
        return try validated(answer, redirects: redirects)
    }

    static func validated<Value>(_ answer: (Value, URLResponse),
                                 redirects: HTTPRedirectGuard) throws -> (Value, URLResponse) {
        if let blocked = redirects.blocked {
            throw blockedRedirect(blocked)
        }
        return answer
    }

    private static func blockedRedirect(_ url: URL) -> APIError {
        APIError(message: L.fmt("http_redirect_blocked", url.absoluteString), status: 403)
    }

    static func publicData(_ req: URLRequest, secureOnly: Bool = false,
                           refusal: String) async throws -> (Data, URLResponse) {
        guard let url = req.url, !secureOnly || url.scheme?.lowercased() == "https",
              !(await URLSafety.isLocalOrPrivateResolved(url)) else {
            throw APIError(message: refusal)
        }
        let answer = try await data(req, secureOnly: secureOnly)
        try ensureSuccess(answer.1)
        try await ensurePublicOrigin(answer.1, secureOnly: secureOnly, refusal: refusal)
        return answer
    }

    static func ensurePublicOrigin(_ response: URLResponse, secureOnly: Bool = false,
                                   refusal: String) async throws {
        guard !secureOnly || response.url?.scheme?.lowercased() == "https",
              !(await URLSafety.isLocalOrPrivateResolved(response.url)) else {
            throw APIError(message: refusal)
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
