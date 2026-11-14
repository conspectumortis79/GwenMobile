import UIKit

@MainActor
protocol DocumentScanning {
    var isSupported: Bool { get }
    func scan() async -> [UIImage]?
}

@MainActor
final class StubDocumentScanner: DocumentScanning {
    var isSupported: Bool { false }
    func scan() async -> [UIImage]? { nil }
}

@MainActor
enum DocumentScannerPort {
    nonisolated(unsafe) static var current: any DocumentScanning = StubDocumentScanner()
}
