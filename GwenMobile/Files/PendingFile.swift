import GwenMobileKit
import Foundation

struct PendingFile: Identifiable {
    var id = UUID()
    let name: String
    let kind: FileKind
    let file: String
    let bytes: Int
    var pages: Int? = nil
    var chars: Int = 0
    var truncated = false
    var via: ExtractionVia = .none
    var reading = true
    var failed = false

    var attached: AttachedFile {
        AttachedFile(file: file, name: name, kind: kind, bytes: bytes, pages: pages,
                     chars: chars, truncated: truncated, via: via)
    }
}
