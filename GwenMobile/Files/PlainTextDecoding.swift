import Foundation

enum PlainTextDecoding {
    private static let utf16Marks: [[UInt8]] = [[0xFF, 0xFE], [0xFE, 0xFF]]

    static func text(of data: Data) -> String {
        if utf16Marks.contains(where: { data.starts(with: $0) }),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) {
            return text
        }
        return String(String.UnicodeScalarView(data.map(Unicode.Scalar.init)))
    }
}
