import XCTest
@testable import GwenMobile

final class WAVCodecTests: XCTestCase {
    func testDecodeParsesHeaderChunksAndReturnsTargetFormatPCM() {
        let samples: [Int16] = [0, 1_000, -1_000, 32_767, -32_768]
        let pcm = samples.withUnsafeBytes { Data($0) }
        let wav = WAVCodec.wav(fromPCM: pcm, sampleRate: WAVCodec.targetSampleRate)
        XCTAssertEqual(Array(wav.prefix(4)), Array("RIFF".utf8))
        XCTAssertEqual(Array(wav.subdata(in: 8..<16)), Array("WAVEfmt ".utf8))
        XCTAssertEqual(WAVCodec.pcm(fromWAV: wav), pcm)
    }

    func testPcmFromShorterThanHeaderReturnsEmpty() {
        XCTAssertEqual(WAVCodec.pcm(fromWAV: Data([0x52, 0x49, 0x46, 0x46])), Data())
    }

    func testTrailingDataWithoutChunksIsReturnedAsPCM() {
        var wav = Data(repeating: 0, count: WAVCodec.headerSize)
        wav.append(contentsOf: [1, 2, 3, 4])
        XCTAssertEqual(WAVCodec.pcm(fromWAV: wav), Data([1, 2, 3, 4]))
    }

    func testNormalizeDownsamplesFromDoubleRate() {
        let samples = (0..<8).map { Int16($0 * 100) }
        let pcm = samples.withUnsafeBytes { Data($0) }
        let out = WAVCodec.normalize(pcm, sampleRate: 32_000, channels: 1, bits: 16)
        XCTAssertEqual(out.count, pcm.count / 2)
        let first = out.subdata(in: 0..<2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        XCTAssertEqual(Int16(bitPattern: first), 0)
    }

    func testNormalizeMixesStereoToMono() {
        var samples = [Int16]()
        for _ in 0..<4 { samples.append(100); samples.append(300) }
        let pcm = samples.withUnsafeBytes { Data($0) }
        let out = WAVCodec.normalize(pcm, sampleRate: WAVCodec.targetSampleRate, channels: 2, bits: 16)
        XCTAssertEqual(out.count, 4 * MemoryLayout<Int16>.size)
        let firstValue = out.subdata(in: 0..<2).withUnsafeBytes { Int16(bitPattern: $0.loadUnaligned(as: UInt16.self)) }
        XCTAssertEqual(firstValue, 200)
    }

    func testWavHeaderReflectsSampleRate() {
        let pcm = Data([1, 2, 3, 4])
        let wav = WAVCodec.wav(fromPCM: pcm, sampleRate: 24_000)
        XCTAssertEqual(wav.count, WAVCodec.headerSize + pcm.count)
        let byteRate = Int(wav.subdata(in: 28..<32).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
        XCTAssertEqual(byteRate, 24_000 * WAVCodec.bytesPerFrame)
    }
}
