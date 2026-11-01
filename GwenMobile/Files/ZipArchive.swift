import GwenMobileKit
import Foundation
import Compression

struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localOffset: Int
    }

    static let maxInflatedBytes = 64_000_000

    private let bytes: Data
    private let entries: [Entry]

    init?(data: Data) {
        let bytes = data.startIndex == 0 ? data : Data(data)
        guard let end = Self.endOfCentralDirectory(in: bytes) else { return nil }
        let count = Self.u16(bytes, end + 10)
        let offset = Self.u32(bytes, end + 16)
        guard count > 0, offset > 0, offset <= bytes.count else { return nil }
        var parsed: [Entry] = []
        var cursor = offset
        for _ in 0..<count {
            guard let stepped = Self.centralEntry(in: bytes, at: cursor) else { return nil }
            parsed.append(stepped.entry)
            cursor = stepped.next
        }
        self.bytes = bytes
        self.entries = parsed
    }

    func data(for name: String) -> Data? {
        guard let entry = entries.first(where: { $0.name == name }) else { return nil }
        let base = entry.localOffset
        guard base >= 0, base + 30 <= bytes.count,
              Self.u32(bytes, base) == 0x0403_4B50 else { return nil }
        let nameLength = Self.u16(bytes, base + 26)
        let extraLength = Self.u16(bytes, base + 28)
        let start = base + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= bytes.count else { return nil }
        let raw = bytes.subdata(in: start..<end)
        switch entry.method {
        case 0: return raw
        case 8: return Self.inflate(raw, size: entry.uncompressedSize)
        default: return nil
        }
    }

    static func endOfCentralDirectory(in data: Data) -> Int? {
        let minimum = 22
        guard data.count >= minimum else { return nil }
        let lowest = max(0, data.count - 65_557)
        var cursor = data.count - minimum
        while cursor >= lowest {
            if u32(data, cursor) == 0x0605_4B50 { return cursor }
            cursor -= 1
        }
        return nil
    }

    private static func centralEntry(in data: Data, at offset: Int) -> (entry: Entry, next: Int)? {
        guard offset >= 0, offset + 46 <= data.count,
              u32(data, offset) == 0x0201_4B50 else { return nil }
        let nameLength = u16(data, offset + 28)
        let extraLength = u16(data, offset + 30)
        let commentLength = u16(data, offset + 32)
        let nameStart = offset + 46
        let nameEnd = nameStart + nameLength
        let next = nameEnd + extraLength + commentLength
        guard nameEnd <= data.count, next <= data.count else { return nil }
        let entry = Entry(name: String(decoding: data[nameStart..<nameEnd], as: UTF8.self),
                          method: UInt16(u16(data, offset + 10)),
                          compressedSize: u32(data, offset + 20),
                          uncompressedSize: u32(data, offset + 24),
                          localOffset: u32(data, offset + 42))
        return (entry, next)
    }

    private static func inflate(_ raw: Data, size: Int) -> Data? {
        guard size > 0, size <= maxInflatedBytes, !raw.isEmpty else { return nil }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let destination = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return raw.withUnsafeBytes { source -> Int in
                guard let source = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destination, size, source, raw.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { return nil }
        return output
    }

    private static func u16(_ data: Data, _ offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
            | (Int(data[offset + 2]) << 16) | (Int(data[offset + 3]) << 24)
    }
}
