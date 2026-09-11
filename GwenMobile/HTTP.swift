import Foundation

struct ProbeResponse: Sendable {
    let status: Int
    let body: Data

    var succeeded: Bool { status < 400 }
    var rejectedByProvider: Bool { status >= 400 && status < 500 }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APITimeout.streamIdle
        config.timeoutIntervalForResource = APITimeout.streamResource
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func endpoint(_ baseURL: String, _ path: String) -> URL? {
        let root = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return URL(string: root + path)
    }

    static func chatCompletionsURL(_ baseURL: String) throws -> URL {
        guard let url = endpoint(baseURL, APIEndpoint.chatCompletions) else {
            throw APIError(message: L.t("bad_url"))
        }
        return url
    }

    static func jsonPOST(url: URL, key: String, body: [String: Any],
                         timeout: TimeInterval, accept: String? = nil) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accept { req.setValue(accept, forHTTPHeaderField: "Accept") }
        authorize(&req, key: key)
        req.timeoutInterval = timeout
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func authorizedGET(url: URL, key: String, timeout: TimeInterval) -> URLRequest {
        var req = URLRequest(url: url)
        authorize(&req, key: key)
        req.timeoutInterval = timeout
        return req
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
    static let connectionRetryBackoff = Duration.milliseconds(1200)

    static func data(_ req: URLRequest, using connection: URLSession = session) async throws -> (Data, URLResponse) {
        do {
            return try await connection.data(for: req)
        } catch let error as URLError where connectionRetryCodes.contains(error.code) {
            try await Task.sleep(for: connectionRetryBackoff)
            return try await connection.data(for: req)
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
