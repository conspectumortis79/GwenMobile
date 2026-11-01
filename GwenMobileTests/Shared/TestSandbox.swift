@testable import GwenMobileFeatureCore
import XCTest
import UIKit
import GwenMobileKit

extension XCTestCase {
    func tempDocuments() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    @MainActor
    func waitUntil(_ condition: @MainActor @escaping () -> Bool,
                   timeout: TimeInterval = 2,
                   file: StaticString = #filePath,
                   line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Bedingung nicht erfuellt innerhalb von \(timeout)s", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    func settle(_ milliseconds: Int = 200) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    @MainActor
    func runProbedActions() {
        for action in TapProbe.drain() { action() }
    }

    func jsonBody(of request: URLRequest) -> [String: Any]? {
        guard let data = request.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func jsonData(of request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
    }

    func jsonMessages(of request: URLRequest) throws -> [[String: Any]] {
        try XCTUnwrap(jsonData(of: request)["messages"] as? [[String: Any]])
    }

    func scratchMediaStore() -> MediaStore {
        let store = MediaStore(paths: StoragePaths(documents: tempDocuments()))
        store.prepareDirectories()
        return store
    }
}

final class EmptyFileManager: FileManager {
    override func urls(for directory: FileManager.SearchPathDirectory,
                       in domainMask: FileManager.SearchPathDomainMask) -> [URL] { [] }
}

enum FakePicture {
    static func make(_ size: CGSize = CGSize(width: 40, height: 20)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

extension FakePicture {
    static func noisy(width: Int, height: Int) -> UIImage? {
        let count = width * height * 4
        var bytes = [UInt8](repeating: 0, count: count)
        var state: UInt32 = 0x9E3779B9
        for index in 0..<count {
            state = state &* 1664525 &+ 1013904223
            bytes[index] = UInt8(truncatingIfNeeded: state >> 24)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        guard let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

enum Fixtures {
    static func source(_ title: String, _ url: String, _ domain: String) -> WebSource {
        WebSource(title: title, url: url, domain: domain)
    }

    static func hit(_ title: String, _ url: String, _ domain: String, _ text: String) -> WebHit {
        WebHit(title: title, url: url, domain: domain, text: text)
    }
}
