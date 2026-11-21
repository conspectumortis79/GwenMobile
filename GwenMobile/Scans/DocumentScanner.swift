import UIKit

@MainActor
final class DocumentScanner {
    static let shared = DocumentScanner()

    #if DEBUG
    var isSupportedOverride: Bool?
    var scanOverride: (() async -> [UIImage]?)?
    #endif

    var isSupported: Bool {
        #if DEBUG
        if let isSupportedOverride { return isSupportedOverride }
        #endif
        return DocumentScannerPort.current.isSupported
    }

    func scan() async -> [UIImage]? {
        #if DEBUG
        if let scanOverride { return await scanOverride() }
        #endif
        return await DocumentScannerPort.current.scan()
    }
}
