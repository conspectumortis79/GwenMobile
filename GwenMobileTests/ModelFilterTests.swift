import XCTest
@testable import GwenMobile

final class ModelFilterTests: XCTestCase {
    private let models = ["qwen3.8-flash", "qwen3.8-max", "qwen-audio-3.0-realtime-plus",
                          "qwen-tts-lite", "wan2.7-image", "qwen-vl-asr-1", "some-image-model"]

    func testTextCandidatesDropAudioTTSAndImageMarkers() {
        XCTAssertEqual(ModelFilter.textCandidates(models),
                       ["qwen3.8-flash", "qwen3.8-max", "qwen-vl-asr-1", "some-image-model"])
    }

    func testImageCandidates() {
        XCTAssertEqual(ModelFilter.imageCandidates(models), ["wan2.7-image", "some-image-model"])
    }

    func testAudioCandidatesKeepASRAndAudioButDropTTS() {
        XCTAssertEqual(ModelFilter.audioCandidates(models), ["qwen-audio-3.0-realtime-plus", "qwen-vl-asr-1"])
    }

    func testEmptyAccountListYieldsNoCandidates() {
        XCTAssertTrue(ModelFilter.textCandidates([]).isEmpty)
        XCTAssertTrue(ModelFilter.imageCandidates([]).isEmpty)
        XCTAssertTrue(ModelFilter.audioCandidates([]).isEmpty)
    }
}
