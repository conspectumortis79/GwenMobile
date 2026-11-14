@testable import GwenMobileFeatureCore
import Foundation
import GwenMobileKit

final class MockHTTPProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data)?)?
    nonisolated(unsafe) static var failure: (@Sendable (URLRequest) -> URLError?)?
    nonisolated(unsafe) static var dataDelay: TimeInterval = 0

    override static func canInit(with request: URLRequest) -> Bool {
        handler != nil
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let failure = Self.failure, let error = failure(request) {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard let handler = Self.handler, let result = handler(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let url = request.url ?? URL(string: "https://mock.test")!
        let response = HTTPURLResponse(url: url, statusCode: result.0, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if Self.dataDelay > 0 { Thread.sleep(forTimeInterval: Self.dataDelay) }
        client?.urlProtocol(self, didLoad: result.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum MockHTTP {
    static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func install(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)?) {
        MockHTTPProtocol.handler = handler
        URLProtocol.registerClass(MockHTTPProtocol.self)
        HTTP.session = HTTP.makeSession(protocolClasses: [MockHTTPProtocol.self])
    }

    static func uninstall() {
        URLProtocol.unregisterClass(MockHTTPProtocol.self)
        MockHTTPProtocol.handler = nil
        MockHTTPProtocol.failure = nil
        MockHTTPProtocol.dataDelay = 0
        HTTP.session = HTTP.makeSession()
    }

    static func failWith(_ failure: @escaping @Sendable (URLRequest) -> URLError?) {
        MockHTTPProtocol.failure = failure
    }

    static func sse(_ text: String) -> Data {
        let object: [String: Any] = ["choices": [["delta": ["content": text]]]]
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return Data(("data: " + String(decoding: body, as: UTF8.self) + "\ndata: [DONE]\n").utf8)
    }

    static func completion(_ text: String) -> Data {
        let object: [String: Any] = ["choices": [["message": ["role": "assistant", "content": text],
                                                 "finish_reason": "stop"]]]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    static func defaultHandler(_ request: URLRequest) -> (Int, Data)? {
        let url = request.url?.absoluteString ?? ""
        if url.contains("chat/completions") || url.contains("/v1/messages") {
            return (200, sse("Erledigt."))
        }
        if url.contains("open-meteo") {
            return (200, Data("{}".utf8))
        }
        if url.contains("itunes.apple.com") {
            return (200, Data("{\"results\":[]}".utf8))
        }
        if url.contains("spotify") {
            return (200, Data("{}".utf8))
        }
        return (200, Data("{}".utf8))
    }
}
