@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ModelFilterTests: XCTestCase {
    private let models = ["qwen3.8-flash", "qwen3.8-max", "qwen-audio-3.0-realtime-plus",
                          "qwen-tts-lite", "wan2.7-image", "qwen-vl-asr-1", "some-image-model",
                          "nomic-embed-text:latest", "text-embedding-3-small"]

    func testTextCandidatesDropAudioTTSImageAndEmbeddingMarkers() {
        XCTAssertEqual(ModelFilter.textCandidates(models),
                       ["qwen3.8-flash", "qwen3.8-max", "qwen-vl-asr-1", "some-image-model"])
    }

    func testImageCandidates() {
        XCTAssertEqual(ModelFilter.imageCandidates(models), ["wan2.7-image", "some-image-model"])
        XCTAssertEqual(ModelFilter.imageCandidates(["wan2.7-image", "wan2.6-t2v"]), ["wan2.7-image"])
    }

    func testEmptyAccountListYieldsNoCandidates() {
        XCTAssertTrue(ModelFilter.textCandidates([]).isEmpty)
        XCTAssertTrue(ModelFilter.imageCandidates([]).isEmpty)
        XCTAssertTrue(ModelFilter.videoCandidates([], caps: [:]).isEmpty)
        XCTAssertTrue(ModelFilter.videoGenerationCandidates([]).isEmpty)
    }

    func testVideoCandidatesNeedConfirmedVideoSupport() {
        let caps: [String: ModelCapabilities] = [
            "qwen3.8-flash": ModelCapabilities(video: .supported),
            "qwen3.8-max": ModelCapabilities(video: .rejected),
        ]
        XCTAssertEqual(ModelFilter.videoCandidates(["qwen3.8-flash", "qwen3.8-max"], caps: caps),
                       ["qwen3.8-flash"])
        XCTAssertTrue(ModelFilter.videoCandidates(["qwen3.8-flash"], caps: [:]).isEmpty)
    }

    func testVideoGenerationCandidatesFindTextAndImageToVideoModels() {
        let all = ["wan2.6-t2v", "wan2.2-i2v-plus", "wan2.7-image", "wan2.7-t2v",
                   "some-video-model", "chat"]
        XCTAssertEqual(ModelFilter.videoGenerationCandidates(all),
                       ["wan2.6-t2v", "wan2.2-i2v-plus", "some-video-model"])
    }
}
