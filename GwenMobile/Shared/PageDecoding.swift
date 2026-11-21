import GwenMobileKit
import Foundation

enum PageDecoding {
    static let sniffedBytes = 2048

    private static let metaCharset = try? NSRegularExpression(
        pattern: "<meta[^>]+charset\\s*=\\s*[\"']?\\s*([A-Za-z0-9_.:-]+)", options: [.caseInsensitive])

    static func text(of data: Data, declared name: String?) -> String {
        if data.contains(0x1B), let encoding = encoding(named: name), encoding != .utf8,
           let text = String(data: data, encoding: encoding) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let encoding = encoding(named: name) ?? encoding(named: sniffedName(in: data)),
           let text = String(data: data, encoding: encoding) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func encoding(named name: String?) -> String.Encoding? {
        guard let name = name?.trimmed, !name.isEmpty else { return nil }
        let found = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard found != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(found))
    }

    static func sniffedName(in data: Data) -> String? {
        guard let metaCharset else { return nil }
        let head = String(decoding: data.prefix(sniffedBytes), as: UTF8.self)
        let source = head as NSString
        guard let match = metaCharset.firstMatch(in: head, range: NSRange(location: 0, length: source.length))
        else { return nil }
        return source.substring(with: match.range(at: 1))
    }
}
