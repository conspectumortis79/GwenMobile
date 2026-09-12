import XCTest
import UIKit
@testable import GwenMobile

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

    func jsonBody(of request: URLRequest) -> [String: Any]? {
        guard let data = request.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
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

enum Fixtures {
    static func source(_ title: String, _ url: String, _ domain: String) -> WebSource {
        WebSource(title: title, url: url, domain: domain)
    }

    static func hit(_ title: String, _ url: String, _ domain: String, _ text: String) -> WebHit {
        WebHit(title: title, url: url, domain: domain, text: text)
    }
}
