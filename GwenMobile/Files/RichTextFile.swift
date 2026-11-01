import GwenMobileKit
import Foundation

struct RichTextContent: Sendable {
    let text: String
    let pictures: [Data]

    var hasPictures: Bool { !pictures.isEmpty }
}

enum RichTextFile {
    private static let pictureMarker: [UInt8] = Array("\\pict".utf8)
    private static let binaryMarker: [UInt8] = Array("\\bin".utf8)
    private static let bitmapMarkers: [[UInt8]] = [Array("pngblip".utf8), Array("jpegblip".utf8)]
    private static let closeBrace: UInt8 = 0x7D
    private static let backslash: UInt8 = 0x5C
    private static let space: UInt8 = 0x20
    private static let tab: UInt8 = 0x09
    private static let zero: UInt8 = 0x30
    private static let minHexChars = 200
    private static let pngHead: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
    private static let jpegHead: [UInt8] = [0xFF, 0xD8, 0xFF]

    static func read(url: URL) -> RichTextContent {
        let attributed = try? NSAttributedString(url: url,
                                                 options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                 documentAttributes: nil)
        let raw = try? Data(contentsOf: url)
        return RichTextContent(text: attributed.map(plainText) ?? "",
                               pictures: pictures(in: raw ?? Data()))
    }

    static func plainText(of attributed: NSAttributedString) -> String {
        attributed.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmed
    }

    static func pictures(in data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var found: [Data] = []
        var cursor = 0
        while let hit = firstRange(of: pictureMarker, in: bytes, from: cursor, limit: bytes.count) {
            guard let end = groupEnd(after: hit.upperBound, in: bytes) else { break }
            cursor = end
            let body = Array(bytes[hit.upperBound..<end])
            guard bitmapMarkers.contains(where: { firstRange(of: $0, in: body, from: 0, limit: body.count) != nil })
            else { continue }
            if let picture = bitmap(from: body) { found.append(picture) }
        }
        return found
    }

    private static func groupEnd(after start: Int, in bytes: [UInt8]) -> Int? {
        guard let close = firstIndex(of: closeBrace, in: bytes, from: start) else { return nil }
        guard let marker = firstRange(of: binaryMarker, in: bytes, from: start, limit: close),
              let length = binaryLength(after: marker.upperBound, in: bytes, limit: close) else { return close }
        let promised = length.start.addingReportingOverflow(length.value)
        guard !promised.overflow else { return bytes.count }
        return promised.partialValue > close ? min(promised.partialValue, bytes.count) : close
    }

    private static func bitmap(from body: [UInt8]) -> Data? {
        if let binary = binaryPayload(from: body) { return isBitmap(binary) ? binary : nil }
        return hexPayload(from: body)
    }

    private static func binaryPayload(from body: [UInt8]) -> Data? {
        guard let marker = firstRange(of: binaryMarker, in: body, from: 0, limit: body.count),
              let length = binaryLength(after: marker.upperBound, in: body, limit: body.count),
              body.count - length.start >= length.value else { return nil }
        return Data(body[length.start..<(length.start + length.value)])
    }

    private struct BinaryLength {
        var value: Int
        var start: Int
    }

    private static func binaryLength(after start: Int, in bytes: [UInt8],
                                     limit: Int) -> BinaryLength? {
        var index = start
        while index < limit, isSpace(bytes[index]) { index += 1 }
        var value = 0
        var digits = 0
        while index < limit, isDigit(bytes[index]) {
            let digit = Int(bytes[index] &- zero)
            guard value <= (Int.max - digit) / 10 else { return nil }
            value = value * 10 + digit
            digits += 1
            index += 1
        }
        guard digits > 0, value > 0 else { return nil }
        if index < limit, bytes[index] == space { index += 1 }
        return BinaryLength(value: value, start: index)
    }

    private static func hexPayload(from body: [UInt8]) -> Data? {
        var hex: [UInt8] = []
        hex.reserveCapacity(body.count)
        var index = 0
        while index < body.count {
            let char = body[index]
            index += 1
            if char == backslash {
                while index < body.count, isLetter(body[index]) { index += 1 }
                while index < body.count, isDigit(body[index]) { index += 1 }
                if index < body.count, body[index] == space { index += 1 }
                continue
            }
            if hexValue(char) != nil { hex.append(char) }
        }
        guard hex.count >= minHexChars else { return nil }
        var bytes = Data(capacity: hex.count / 2)
        var position = 0
        while hex.count - position >= 2 {
            guard let high = hexValue(hex[position]), let low = hexValue(hex[position + 1]) else { break }
            bytes.append(high << 4 | low)
            position += 2
        }
        return isBitmap(bytes) ? bytes : nil
    }

    private static func firstRange(of marker: [UInt8], in bytes: [UInt8],
                                   from start: Int, limit: Int) -> Range<Int>? {
        guard !marker.isEmpty, limit - start >= marker.count else { return nil }
        var index = start
        while index + marker.count <= limit {
            if bytes[index..<(index + marker.count)].elementsEqual(marker) {
                return index..<(index + marker.count)
            }
            index += 1
        }
        return nil
    }

    static func firstIndex(of byte: UInt8, in bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        while index < bytes.count {
            if bytes[index] == byte { return index }
            index += 1
        }
        return nil
    }

    private static func liesBetween(_ byte: UInt8, _ low: UInt8, _ high: UInt8) -> Bool {
        byte >= low && byte <= high
    }

    private static func isDigit(_ byte: UInt8) -> Bool { liesBetween(byte, zero, 0x39) }

    private static func isSpace(_ byte: UInt8) -> Bool { byte == space || byte == tab }

    private static func isLetter(_ byte: UInt8) -> Bool {
        liesBetween(byte, 0x41, 0x5A) || liesBetween(byte, 0x61, 0x7A)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        if isDigit(byte) { return byte - zero }
        if liesBetween(byte, 0x41, 0x46) { return byte - 0x41 + 10 }
        if liesBetween(byte, 0x61, 0x66) { return byte - 0x61 + 10 }
        return nil
    }

    private static func isBitmap(_ bytes: Data) -> Bool {
        Array(bytes.prefix(pngHead.count)) == pngHead || Array(bytes.prefix(jpegHead.count)) == jpegHead
    }
}
