@testable import GwenMobileFeatureCore
import Foundation
import XCTest

final class LocalDownloadCancellationTests: XCTestCase {
    private class StubProtocol: URLProtocol {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var requestCount = 0
        private var work: DispatchWorkItem?

        static var requests: Int {
            lock.lock()
            defer { lock.unlock() }
            return requestCount
        }

        static func reset() {
            lock.lock()
            requestCount = 0
            lock.unlock()
        }

        override class func canInit(with request: URLRequest) -> Bool { true }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            Self.requestCount += 1
            Self.lock.unlock()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard let url = self.request.url,
                      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                     headerFields: nil) else {
                    self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                    return
                }
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: Data("test".utf8))
                self.client?.urlProtocolDidFinishLoading(self)
            }
            self.work = work
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: work)
        }

        override func stopLoading() {
            work?.cancel()
            work = nil
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testCancellingBeforeStartPreventsTheDownload() async throws {
        StubProtocol.reset()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("download.bin")
        let transfer = LocalFileTransfer(destination: destination, progress: { _, _ in })
        transfer.cancel()
        do {
            try await transfer.start(url: try XCTUnwrap(URL(string: "https://download.test/file")),
                                     session: makeSession())
            XCTFail("download should have been cancelled")
        } catch is CancellationError {
        }
        XCTAssertEqual(StubProtocol.requests, 0)
    }

    func testCancellingTheParentTaskStopsTheTransfer() async throws {
        StubProtocol.reset()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("download.bin")
        let transfer = LocalFileTransfer(destination: destination, progress: { _, _ in })
        let url = try XCTUnwrap(URL(string: "https://download.test/file"))
        let session = makeSession()
        let task = Task {
            try await transfer.start(url: url, session: session)
        }
        try await Task.sleep(for: .milliseconds(40))
        transfer.cancel()
        do {
            try await task.value
            XCTFail("download should have been cancelled")
        } catch is CancellationError {
        }
        XCTAssertGreaterThanOrEqual(StubProtocol.requests, 1)
    }
}
