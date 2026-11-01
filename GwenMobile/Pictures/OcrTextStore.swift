import GwenMobileKit
import Foundation

struct OcrFile: Codable, Equatable, Hashable, Sendable {
    var file: String
    var chars: Int

    enum CodingKeys: String, CodingKey {
        case file, chars
    }
}

extension OcrFile {
    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        file = fields.content(String.self, .file, fallback: "")
        chars = fields.content(Int.self, .chars, fallback: 0)
    }

    var displayName: String { (file as NSString).lastPathComponent }

    var metaText: String {
        "\(L.t("ocr_badge")) · \(L.fmt("ocr_chars", Formatters.countText(chars)))"
    }
}

enum OcrTextStore {
    static let folder = "ocr"

    static func name(imageDate: Date, suffix: String = "") -> String {
        let stamp = Formatters.fileStamp(imageDate)
        return suffix.isEmpty ? "text_\(stamp).jpg.txt" : "text_\(stamp)_\(suffix).jpg.txt"
    }

    static var temporaryRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(folder, isDirectory: true)
    }

    #if DEBUG
    static func documentsURL(for file: String, paths: StoragePaths = StoragePaths()) -> URL {
        paths.ocr.appendingPathComponent(file)
    }
    #endif

    static func temporaryFile(named file: String, text: String) -> URL? {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            let url = temporaryRoot.appendingPathComponent(file)
            guard let data = text.data(using: .utf8) else { return nil }
            try data.write(to: url)
            return url
        } catch {
            flowLog.error("OCR temporär schreiben fehlgeschlagen \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func removeStoredText(from urls: [URL] = [StoragePaths().ocr, OcrTextStore.temporaryRoot]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
