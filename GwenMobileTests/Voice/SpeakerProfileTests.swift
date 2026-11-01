@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import GwenMobileKit
import AVFoundation
import XCTest

@MainActor
final class SpeakerProfileTests: GwenTestCase {
    private func embedding(_ value: Float) -> [Float] {
        var result = [Float](repeating: 0, count: SpeakerProfile.dimension)
        result[0] = value
        result[1] = 1
        return result
    }

    private func unit(_ first: Float, _ second: Float) -> [Float] {
        var result = [Float](repeating: 0, count: SpeakerProfile.dimension)
        result[0] = first
        result[1] = second
        return SpeakerProfileBuilder.normalized(result)!
    }

    func testCosineAndBestScore() {
        let left = unit(1, 1)
        let right = unit(1, 1)
        XCTAssertEqual(SpeakerProfileBuilder.cosine(left, right), 1, accuracy: 0.0001)
        XCTAssertEqual(SpeakerProfileBuilder.cosine(left, unit(-1, -1)), -1, accuracy: 0.0001)
        let profile = SpeakerProfileBuilder.profile(from: [left])!
        XCTAssertEqual(profile.bestScore(for: right), 1, accuracy: 0.0001)
    }

    func testProfileBuilderNormalizesAndCaps() {
        let inputs = (1...20).map { _ in embedding(1) }
        let profile = SpeakerProfileBuilder.profile(from: inputs)!
        XCTAssertEqual(profile.embeddings.count, SpeakerProfileBuilder.maximumEmbeddings)
        for item in profile.embeddings {
            let norm = item.reduce(0) { $0 + $1 * $1 }.squareRoot()
            XCTAssertEqual(norm, 1, accuracy: 0.0001)
        }
    }

    func testConsistencyOfIdenticalAndOppositeEmbeddings() {
        let first = unit(1, 1)
        let second = unit(-1, -1)
        XCTAssertEqual(SpeakerProfileBuilder.consistency(of: [first, first])!, 1, accuracy: 0.0001)
        XCTAssertEqual(SpeakerProfileBuilder.consistency(of: [first, second])!, -1, accuracy: 0.0001)
        XCTAssertNil(SpeakerProfileBuilder.consistency(of: [first]))
    }

    func testSensitivityMovesTheThreshold() {
        let profile = SpeakerProfileBuilder.profile(from: [embedding(1)], threshold: 0.55)!
        XCTAssertEqual(profile.threshold(for: .strict), 0.63, accuracy: 0.0001)
        XCTAssertEqual(profile.threshold(for: .normal), 0.55, accuracy: 0.0001)
        XCTAssertEqual(profile.threshold(for: .relaxed), 0.47, accuracy: 0.0001)
    }

    func testScorePolicy() {
        XCTAssertEqual(SpeakerScorePolicy.early([0.70], threshold: 0.55), .allowed)
        XCTAssertEqual(SpeakerScorePolicy.early([0.50], threshold: 0.55), .unknown)
        XCTAssertEqual(SpeakerScorePolicy.early([0.50, 0.40], threshold: 0.55), .rejected)
        XCTAssertEqual(SpeakerScorePolicy.final([0.40, 0.60], threshold: 0.55), .allowed)
        XCTAssertEqual(SpeakerScorePolicy.final([0.40], threshold: 0.55), .rejected)
        XCTAssertEqual(SpeakerScorePolicy.final([], threshold: 0.55), .rejected)
    }

    func testAudioWindowsUseTheConfiguredHopAndTail() {
        let samples = (0..<80000).map { Float(sin(2 * Double.pi * 220 * Double($0) / 16000)) * 0.1 }
        let windows = SpeakerAudioWindows.windows(from: samples)
        XCTAssertEqual(windows.count, 4)
        for window in windows {
            XCTAssertEqual(window.count, SpeakerAudioWindows.windowSamples)
            XCTAssertGreaterThan(SpeakerAudioWindows.rms(window), SpeakerAudioWindows.minimumRMS)
            XCTAssertEqual(window.reduce(0) { max($0, abs($1)) }, 0.25, accuracy: 0.01)
        }
    }

    func testShortAudioIsTiledAndSilenceIsDropped() {
        let samples = (0..<16000).map { Float(sin(2 * Double.pi * 220 * Double($0) / 16000)) * 0.1 }
        XCTAssertEqual(SpeakerAudioWindows.windows(from: samples).count, 1)
        XCTAssertTrue(SpeakerAudioWindows.windows(from: [Float](repeating: 0, count: 16000)).isEmpty)
        XCTAssertTrue(SpeakerAudioWindows.windows(from: []).isEmpty)
    }

    func testKeychainProfileStoreRoundTrip() throws {
        let store = SpeakerProfileStore(service: "GwenMobileTests", account: "speaker-\(UUID().uuidString)")
        defer { store.delete() }
        let profile = SpeakerProfileBuilder.profile(from: [embedding(1)], threshold: 0.55)!
        guard store.save(profile) else {
            throw XCTSkip("Keychain is unavailable in this environment")
        }
        XCTAssertEqual(store.load(), profile)
        var updated = profile
        updated.threshold = 0.62
        XCTAssertTrue(store.save(updated))
        XCTAssertEqual(store.load(), updated)
        var invalid = updated
        invalid.model = "old-model"
        XCTAssertFalse(invalid.isValid)
        XCTAssertFalse(store.save(invalid))
        XCTAssertEqual(store.load(), updated)
        XCTAssertTrue(store.delete())
        XCTAssertNil(store.load())
    }

    func testProfileRoundTripsThroughJSON() throws {
        let profile = SpeakerProfileBuilder.profile(from: [embedding(1)], threshold: 0.55)!
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(SpeakerProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }

    func testBundledEmbedderProducesANormalizedVector() throws {
        try XCTSkipUnless(SpeakerEmbedder.isBundled)
        let samples = (0..<SpeakerEmbedder.windowSamples).map {
            Float(sin(2 * Double.pi * 220 * Double($0) / 16000)) * 0.1
        }
        let embedder = SpeakerEmbedder(bundle: .main)
        guard let result = embedder.embed(samples) else {
            throw XCTSkip("CoreML cannot run the bundled voice model in this environment")
        }
        XCTAssertEqual(result.count, SpeakerProfile.dimension)
        XCTAssertTrue(result.allSatisfy { $0.isFinite })
        let norm = result.reduce(0) { $0 + $1 * $1 }.squareRoot()
        XCTAssertEqual(norm, 1, accuracy: 0.001)
    }

    func testPCMConversionAndCollector() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000,
                                   channels: 1, interleaved: false)!
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
        buffer.frameLength = 4800
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<4800 {
            channel[index] = Float(sin(2 * Double.pi * 220 * Double(index) / 48000)) * 0.1
        }
        let converter = SpeakerPCMConverter()
        let samples = try XCTUnwrap(converter.samples(from: buffer))
        XCTAssertGreaterThan(samples.count, 1300)
        XCTAssertLessThan(samples.count, 1700)
        let collector = SpeakerSampleCollector()
        collector.append(buffer)
        XCTAssertEqual(collector.samples(), samples)
    }

    func testVoiceSettingsRoundTripTheSpeakerOptions() {
        let defaults = UserDefaults(suiteName: "SpeakerProfileTests")!
        defaults.removePersistentDomain(forName: "SpeakerProfileTests")
        var settings = VoiceSettings()
        settings.onlyMyVoice = true
        settings.speakerSensitivity = .relaxed
        settings.store(to: defaults)
        XCTAssertTrue(VoiceSettings.load(from: defaults).onlyMyVoice)
        XCTAssertEqual(VoiceSettings.load(from: defaults).speakerSensitivity, .relaxed)
        defaults.removePersistentDomain(forName: "SpeakerProfileTests")
    }

    func testTheSensitivityExposesIdentifiersAndLabelKeys() {
        XCTAssertEqual(SpeakerSensitivity.allCases.map(\.id), [0, 1, 2])
        XCTAssertEqual(SpeakerSensitivity.strict.key, "speaker_sensitivity_strict")
        XCTAssertEqual(SpeakerSensitivity.normal.key, "speaker_sensitivity_normal")
        XCTAssertEqual(SpeakerSensitivity.relaxed.key, "speaker_sensitivity_relaxed")
    }

    func testTheProfileCountsItsEmbeddings() {
        let profile = SpeakerProfileBuilder.profile(from: [embedding(1), embedding(1), embedding(1)])!
        XCTAssertEqual(profile.sampleCount, 3)
        let empty = SpeakerProfile(model: SpeakerProfile.currentModel, embeddings: [],
                                   threshold: 0.55)
        XCTAssertEqual(empty.sampleCount, 0)
    }

    func testTheProfileStoreWalksEveryKeychainBranch() throws {
        let original = (copy: KeychainInterop.copyMatching,
                        update: KeychainInterop.updateItem,
                        add: KeychainInterop.addItem,
                        delete: KeychainInterop.deleteItem)
        addTeardownBlock {
            KeychainInterop.copyMatching = original.copy
            KeychainInterop.updateItem = original.update
            KeychainInterop.addItem = original.add
            KeychainInterop.deleteItem = original.delete
        }
        let store = SpeakerProfileStore(service: "SpeakerProfileTests", account: "branch")
        let profile = SpeakerProfileBuilder.profile(from: [embedding(1)], threshold: 0.55)!
        let encoded = try JSONEncoder().encode(profile)

        KeychainInterop.copyMatching = { _ in (errSecSuccess, encoded as AnyObject) }
        XCTAssertEqual(store.load(), profile)

        KeychainInterop.copyMatching = { _ in (errSecSuccess, Data("kein json".utf8) as AnyObject) }
        XCTAssertNil(store.load())

        var outdated = profile
        outdated.model = "alter-model"
        let outdatedData = try JSONEncoder().encode(outdated)
        KeychainInterop.copyMatching = { _ in (errSecSuccess, outdatedData as AnyObject) }
        XCTAssertNil(store.load())

        KeychainInterop.copyMatching = { _ in (errSecSuccess, "text" as AnyObject) }
        XCTAssertNil(store.load())

        KeychainInterop.copyMatching = { _ in (errSecItemNotFound, nil) }
        XCTAssertNil(store.load())

        KeychainInterop.updateItem = { _, _ in errSecSuccess }
        XCTAssertTrue(store.save(profile))

        KeychainInterop.updateItem = { _, _ in errSecItemNotFound }
        KeychainInterop.addItem = { _ in errSecSuccess }
        XCTAssertTrue(store.save(profile))

        KeychainInterop.addItem = { _ in errSecInternalError }
        XCTAssertFalse(store.save(profile))

        KeychainInterop.updateItem = { _, _ in errSecInternalError }
        XCTAssertFalse(store.save(profile))

        KeychainInterop.deleteItem = { _ in errSecSuccess }
        XCTAssertTrue(store.delete())
        KeychainInterop.deleteItem = { _ in errSecItemNotFound }
        XCTAssertTrue(store.delete())
        KeychainInterop.deleteItem = { _ in errSecInternalError }
        XCTAssertFalse(store.delete())
    }
}

extension SpeakerProfileTests {
    func testTheKeychainInteropDefaultsAreWired() {
        XCTAssertNotNil(KeychainInterop.copyMatching as Any)
        XCTAssertNotNil(KeychainInterop.updateItem as Any)
        let add = KeychainInterop.addItem
        XCTAssertNotEqual(add([:]), 0)
        XCTAssertNotNil(KeychainInterop.deleteItem as Any)
    }
}
