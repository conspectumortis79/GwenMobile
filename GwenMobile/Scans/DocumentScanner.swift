import UIKit

@MainActor
final class DocumentScanner {
    static let shared = DocumentScanner()

    var isSupportedOverride: Bool?
    var scanOverride: (() async -> [UIImage]?)?

    var isSupported: Bool {
        if let isSupportedOverride { return isSupportedOverride }
        return DocumentScannerPort.current.isSupported
    }

    func scan() async -> [UIImage]? {
        if let scanOverride { return await scanOverride() }
        return await DocumentScannerPort.current.scan()
    }
}
