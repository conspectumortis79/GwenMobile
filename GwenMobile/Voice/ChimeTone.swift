import GwenMobileKit
import Foundation

struct ChimeNote: Equatable, Sendable {
    let frequency: Double
    let seconds: Double
}

struct ChimeTone: Equatable, Sendable {
    static let sampleRate = 44_100
    static let sent = ChimeTone(name: "sendeton", notes: [ChimeNote(frequency: 1_318.5, seconds: 0.08),
                                                         ChimeNote(frequency: 880, seconds: 0.14)],
                                volume: 0.6, fade: 0.012)

    let name: String
    let notes: [ChimeNote]
    let volume: Double
    let fade: Double

    var samples: [Int16] { notes.flatMap(samples(of:)) }

    private func samples(of note: ChimeNote) -> [Int16] {
        let rate = Double(Self.sampleRate)
        let count = Int((note.seconds * rate).rounded())
        let edge = Double(max(1, Int((fade * rate).rounded())))
        return (0..<count).map { index in
            let envelope = min(1, Double(index) / edge, Double(count - 1 - index) / edge)
            let wave = sin(2 * Double.pi * note.frequency * Double(index) / rate)
            return Int16((wave * envelope * volume * Double(Int16.max)).rounded())
        }
    }
}

enum WaveFile {
    static let headerSize = 44

    static func pcm16(_ samples: [Int16], sampleRate: Int) -> Data {
        let payload = samples.count * MemoryLayout<Int16>.size
        var data = Data(capacity: headerSize + payload)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(headerSize - 8 + payload), to: &data)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * MemoryLayout<Int16>.size), to: &data)
        append(UInt16(MemoryLayout<Int16>.size), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(payload), to: &data)
        samples.forEach { append($0, to: &data) }
        return data
    }

    private static func append<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
