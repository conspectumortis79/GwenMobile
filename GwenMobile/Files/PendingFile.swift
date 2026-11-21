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

    init(name: String, kind: FileKind, file: String, bytes: Int,
         pages: Int? = nil, chars: Int = 0, truncated: Bool = false,
         via: ExtractionVia = .none, reading: Bool = true, failed: Bool = false) {
        self.name = name
        self.kind = kind
        self.file = file
        self.bytes = bytes
        self.pages = pages
        self.chars = chars
        self.truncated = truncated
        self.via = via
        self.reading = reading
        self.failed = failed
    }

    init(_ attached: AttachedFile) {
        self.init(name: attached.name, kind: attached.kind, file: attached.file,
                  bytes: attached.bytes, pages: attached.pages, chars: attached.chars,
                  truncated: attached.truncated, via: attached.via, reading: false)
    }

    var attached: AttachedFile {
        AttachedFile(file: file, name: name, kind: kind, bytes: bytes, pages: pages,
                     chars: chars, truncated: truncated, via: via)
    }
}
