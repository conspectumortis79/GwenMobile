import GwenMobileKit
import Foundation
import UniformTypeIdentifiers

enum FileKind: String, Codable, Equatable, Sendable {
    case pdf
    case rtf
    case docx
    case text
    case csv
    case json
    case video

    init?(filename: String) {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": self = .pdf
        case "rtf": self = .rtf
        case "docx": self = .docx
        case "csv", "tsv": self = .csv
        case "json": self = .json
        case "txt", "md", "markdown", "log": self = .text
        case "mp4", "mov", "m4v", "webm", "mpeg", "mpg": self = .video
        default: return nil
        }
    }
}

extension FileKind {
    static let importTypes: [UTType] = [.pdf, .rtf, .text, .plainText, .commaSeparatedText, .json, .movie]
        + [UTType(filenameExtension: "docx"), UTType(filenameExtension: "webm")].compactMap { $0 }
    static let videoImportTypes: [UTType] = [.movie]
        + [UTType(filenameExtension: "webm")].compactMap { $0 }
}

enum ExtractionVia: String, Codable, Equatable, Sendable {
    case textLayer
    case richText
    case docx
    case ocr
    case plain
    case none

    var privacyKey: String? {
        switch self {
        case .textLayer: return "file_local_pdfkit"
        case .richText: return "file_local_rich"
        case .docx: return "file_local_docx"
        case .ocr: return "file_local_ocr"
        case .plain: return "file_local_plain"
        case .none: return nil
        }
    }
}

struct AttachedFile: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID = UUID()
    var file: String
    var name: String
    var kind: FileKind
    var bytes: Int
    var pages: Int? = nil
    var chars: Int = 0
    var truncated: Bool = false
    var via: ExtractionVia = .none

    enum CodingKeys: String, CodingKey {
        case id, file, name, kind, bytes, pages, chars, truncated, via
    }
}

extension AttachedFile {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        id = fields.metadata(UUID.self, .id, fallback: UUID())
        file = fields.content(String.self, .file, fallback: "")
        name = fields.content(String.self, .name, fallback: "")
        kind = fields.content(FileKind.self, .kind, fallback: .text)
        bytes = fields.metadata(Int.self, .bytes, fallback: 0)
        pages = fields.metadata(Int.self, .pages)
        chars = fields.content(Int.self, .chars, fallback: 0)
        truncated = fields.metadata(Bool.self, .truncated, fallback: false)
        via = fields.content(ExtractionVia.self, .via, fallback: .none)
    }

    var hasText: Bool { chars > 0 }

    var isVideo: Bool { kind == .video }

    var pagesDetail: String? {
        guard let pages, pages > 1 else { return nil }
        return L.fmt("file_pages_range", String(pages))
    }

    var metaText: String {
        if kind == .video {
            return StorageUsage.joined([L.t("file_video"), StorageUsage.bytesText(bytes)])
        }
        var parts: [String] = []
        if let pages { parts.append(L.counted(pages, one: "file_pages_one", many: "file_pages")) }
        parts.append(StorageUsage.bytesText(bytes))
        if truncated {
            parts.append(L.fmt("file_truncated", Formatters.countText(chars)))
        } else if via == .ocr, chars > 0 {
            parts.append(L.fmt("file_ocr_read", Formatters.countText(chars)))
        } else if chars > 0 {
            parts.append(L.fmt("file_text_read", Formatters.countText(chars)))
        } else {
            parts.append(L.t("file_no_text"))
        }
        return StorageUsage.joined(parts)
    }
}

struct FileRef: Codable, Equatable, Hashable, Sendable {
    var name: String
    var detail: String? = nil
    var via: ExtractionVia = .none

    enum CodingKeys: String, CodingKey {
        case name, detail, via
    }
}

extension FileRef {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        name = fields.content(String.self, .name, fallback: "")
        detail = fields.metadata(String.self, .detail)
        via = fields.metadata(ExtractionVia.self, .via, fallback: .none)
    }

    init(_ file: AttachedFile) {
        name = file.name
        detail = file.pagesDetail
        via = file.via
    }

    var chipText: String {
        detail.map { "\(name) · \($0)" } ?? name
    }

    var privacyKey: String? { via.privacyKey }
}
