@testable import GwenMobileFeatureCore
import AVFoundation
import XCTest
import GwenMobileKit

final class ChimeToneTests: XCTestCase {
    private let tone = ChimeTone.sent

    private var expectedCount: Int {
        tone.notes.map { Int(($0.seconds * Double(ChimeTone.sampleRate)).rounded()) }.reduce(0, +)
    }

    func testTheToneIsShortSoItDoesNotCoverTheRequest() {
        let seconds = tone.notes.map(\.seconds).reduce(0, +)
        XCTAssertLessThanOrEqual(seconds, 0.3)
        XCTAssertEqual(tone.samples.count, expectedCount)
    }

    func testTheToneFallsInFrequency() {
        let frequencies = tone.notes.map(\.frequency)
        XCTAssertGreaterThan(frequencies[0], frequencies[1])
    }

    func testEveryNoteFadesInAndOutWithoutAClick() {
        let samples = tone.samples
        let firstNote = Int((tone.notes[0].seconds * Double(ChimeTone.sampleRate)).rounded())
        XCTAssertEqual(samples.first, 0)
        XCTAssertEqual(samples.last, 0)
        XCTAssertEqual(samples[firstNote], 0, "auch der zweite Ton beginnt leise")
        XCTAssertLessThanOrEqual(abs(Int(samples[firstNote - 1])), 1)
    }

    func testTheLoudestSampleStaysBelowTheChosenVolume() {
        let peak = tone.samples.map { abs(Int($0)) }.max() ?? 0
        let ceiling = tone.volume * Double(Int16.max)
        XCTAssertLessThanOrEqual(Double(peak), ceiling.rounded())
        XCTAssertGreaterThan(Double(peak), ceiling * 0.9)
    }
}

final class WaveFileTests: XCTestCase {
    private func word(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<offset + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }

    private func half(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    func testTheHeaderDescribesMono16BitPCM() {
        let data = WaveFile.pcm16([0, 1, -1, Int16.max], sampleRate: 44_100)
        XCTAssertEqual(data.count, WaveFile.headerSize + 8)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(word(data, at: 4), UInt32(data.count - 8))
        XCTAssertEqual(String(decoding: data[8..<16], as: UTF8.self), "WAVEfmt ")
        XCTAssertEqual(half(data, at: 20), 1)
        XCTAssertEqual(half(data, at: 22), 1)
        XCTAssertEqual(word(data, at: 24), 44_100)
        XCTAssertEqual(word(data, at: 28), 88_200)
        XCTAssertEqual(half(data, at: 32), 2)
        XCTAssertEqual(half(data, at: 34), 16)
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
        XCTAssertEqual(word(data, at: 40), 8)
        XCTAssertEqual(half(data, at: 44 + 4), UInt16(bitPattern: -1))
    }

    func testTheSystemPlayerAcceptsTheChimeTone() throws {
        let data = WaveFile.pcm16(ChimeTone.sent.samples, sampleRate: ChimeTone.sampleRate)
        let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
        let seconds = ChimeTone.sent.notes.map(\.seconds).reduce(0, +)
        XCTAssertEqual(player.duration, seconds, accuracy: 0.01)
    }
}
