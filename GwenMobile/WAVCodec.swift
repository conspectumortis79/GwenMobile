import Foundation

enum WAVCodec {
    static let targetSampleRate = 16000
    static let targetChannels = 1
    static let targetBitsPerSample = 16
    static let headerSize = 44
    static let fmtChunk = "fmt "
    static let dataChunk = "data"
    static let bytesPerFrame = 2

    static func pcm(fromWAV wav: Data) -> Data {
        guard wav.count > headerSize else { return Data() }
        var offset = 12
        var sampleRate = targetSampleRate
        var channels = targetChannels
        var bits = targetBitsPerSample
        while offset + 8 <= wav.count {
            let id = String(decoding: wav.subdata(in: offset..<offset + 4), as: UTF8.self)
            let size = readInt32(wav, at: offset + 4)
            if id == fmtChunk, offset + 8 + 16 <= wav.count {
                let f = offset + 8
                channels = readInt16(wav, at: f + 2)
                sampleRate = readInt32(wav, at: f + 4)
                bits = readInt16(wav, at: f + 14)
            } else if id == dataChunk {
                let start = offset + 8
                let end = min(start + size, wav.count)
                guard start < end else { return Data() }
                let pcm = wav.subdata(in: start..<end)
                if sampleRate == targetSampleRate, channels == targetChannels, bits == targetBitsPerSample { return pcm }
                return normalize(pcm, sampleRate: sampleRate, channels: channels, bits: bits)
            }
            offset += 8 + size + (size % 2)
        }
        return wav.count > headerSize ? wav.subdata(in: headerSize..<wav.count) : Data()
    }

    static func wav(fromPCM pcm: Data, sampleRate: Int) -> Data {
        var data = Data()
        let dataLength = pcm.count
        data.append(contentsOf: ascii("RIFF"))
        data.append(contentsOf: bytes(UInt32(36 + dataLength)))
        data.append(contentsOf: ascii("WAVE\(fmtChunk)"))
        data.append(contentsOf: bytes(UInt32(16)))
        data.append(contentsOf: bytes(UInt16(1)))
        data.append(contentsOf: bytes(UInt16(targetChannels)))
        data.append(contentsOf: bytes(UInt32(sampleRate)))
        data.append(contentsOf: bytes(UInt32(sampleRate * bytesPerFrame)))
        data.append(contentsOf: bytes(UInt16(bytesPerFrame)))
        data.append(contentsOf: bytes(UInt16(targetBitsPerSample)))
        data.append(contentsOf: ascii(dataChunk))
        data.append(contentsOf: bytes(UInt32(dataLength)))
        data.append(pcm)
        return data
    }

    static func normalize(_ pcm: Data, sampleRate: Int, channels: Int, bits: Int) -> Data {
        let bytesPerSample = max(bits / 8, 2)
        let step = bytesPerSample * max(channels, 1)
        guard step > 0, pcm.count >= step else { return Data() }
        var mono = [Int16]()
        mono.reserveCapacity(pcm.count / step)
        for i in stride(from: 0, through: pcm.count - step, by: step) {
            if channels == targetChannels {
                mono.append(sample(from: pcm, at: i))
            } else {
                var sum = 0
                for c in 0..<channels { sum += Int(sample(from: pcm, at: i + c * bytesPerSample)) }
                mono.append(Int16(clamping: sum / max(channels, 1)))
            }
        }
        guard sampleRate > 0, sampleRate != targetSampleRate, !mono.isEmpty else { return data(from: mono) }
        let ratio = Double(sampleRate) / Double(targetSampleRate)
        var out = [Int16](repeating: 0, count: max(Int(Double(mono.count) / ratio), 0))
        for j in 0..<out.count {
            let srcPos = Double(j) * ratio
            let i0 = Int(srcPos)
            let i1 = min(i0 + 1, mono.count - 1)
            let frac = srcPos - Double(i0)
            out[j] = Int16(clamping: Int(Double(mono[i0]) * (1 - frac) + Double(mono[i1]) * frac))
        }
        return data(from: out)
    }

    private static func data(from samples: [Int16]) -> Data {
        samples.withUnsafeBytes { Data($0) }
    }

    private static func sample(from data: Data, at offset: Int) -> Int16 {
        Int16(bitPattern: u16(from: data, at: offset))
    }

    private static func u16(from data: Data, at offset: Int) -> UInt16 {
        data.subdata(in: offset..<offset + 2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).littleEndian }
    }

    private static func readInt16(_ data: Data, at offset: Int) -> Int {
        Int(u16(from: data, at: offset))
    }

    private static func readInt32(_ data: Data, at offset: Int) -> Int {
        Int(data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
    }

    private static func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }

    private static func bytes(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }

    private static func bytes(_ v: UInt16) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
}
