import Foundation

enum PlainTextDecoding {
    private static let utf16Marks: [[UInt8]] = [[0xFF, 0xFE], [0xFE, 0xFF]]

    static func text(of data: Data) -> String {
        if utf16Marks.contains(where: { data.starts(with: $0) }),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let encoding = utf16Encoding(of: data),
           let text = String(data: data, encoding: encoding) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) {
            return text
        }
        return String(String.UnicodeScalarView(data.map(Unicode.Scalar.init)))
    }

    private static func utf16Encoding(of data: Data) -> String.Encoding? {
        guard data.count >= 4, data.count % 2 == 0 else { return nil }
        var evenZeros = 0
        var oddZeros = 0
        for (offset, byte) in data.enumerated() where byte == 0 {
            if offset % 2 == 0 { evenZeros += 1 } else { oddZeros += 1 }
        }
        let pairs = data.count / 2
        if oddZeros * 2 >= pairs, evenZeros * 2 < pairs { return .utf16LittleEndian }
        if evenZeros * 2 >= pairs, oddZeros * 2 < pairs { return .utf16BigEndian }
        return nil
    }
}
