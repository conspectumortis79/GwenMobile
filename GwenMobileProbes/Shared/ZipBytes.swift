#if DEBUG
import Foundation

enum ZipBytes {
    static func le16(_ value: Int) -> Data {
        Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff)])
    }

    static func le32(_ value: Int) -> Data {
        Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff),
              UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)])
    }

    static func entryFields(size: Int, nameLength: Int) -> Data {
        var header = Data()
        header.append(le16(20))
        header.append(le16(0))
        header.append(le16(0))
        header.append(le16(0))
        header.append(le16(0))
        header.append(le32(0))
        header.append(le32(size))
        header.append(le32(size))
        header.append(le16(nameLength))
        header.append(le16(0))
        return header
    }
}
#endif
