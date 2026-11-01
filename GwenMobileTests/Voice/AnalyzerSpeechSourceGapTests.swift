@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AVFoundation
import Speech
import XCTest
import GwenMobileKit

@MainActor
private final class AnalyzerFakeFeed: AudioFeeding, @unchecked Sendable {
    private let running = LockedValue(false)
    var failure: Error?

    var isRunning: Bool { running.current }

    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        if let failure { throw failure }
        running.set(true)
    }

    func stop() { running.set(false) }
}

@MainActor
private final class FakeSpeechSession: SpeechAnalysisSessioning {
    var prepared: [String] = []
    var format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    var pieces: [SpeechPiece] = [SpeechPiece(text: "Hallo", isFinal: false),
                                 SpeechPiece(text: "Hallo Welt", isFinal: true)]
    var failure: Error?
    var startFailure: Error?
    var streamFailure: Error?
    var finishFailure: Error?
    private(set) var cancelled = 0
    private(set) var finished = 0
    private var continuation: AsyncThrowingStream<SpeechPiece, Error>.Continuation?

    func prepare(hints: [String]) async throws -> AVAudioFormat {
        if let failure { throw failure }
        prepared = hints
        return format
    }

    func start(input: AsyncStream<AnalyzerInput>) async throws -> AsyncThrowingStream<SpeechPiece, Error> {
        if let startFailure { throw startFailure }
        if let failure { throw failure }
        let (stream, continuation) = AsyncThrowingStream<SpeechPiece, Error>.makeStream()
        self.continuation = continuation
        for piece in pieces { continuation.yield(piece) }
        if let streamFailure {
            continuation.finish(throwing: streamFailure)
        } else {
            continuation.finish()
        }
        return stream
    }

    func finish() async throws {
        finished += 1
        if let finishFailure { throw finishFailure }
    }

    func cancel() async {
        cancelled += 1
        continuation?.finish()
    }
}

@MainActor
final class AnalyzerSpeechSourceGapTests: GwenTestCase {
    func testTheAnalyzerSourceReadsPiecesAndFails() async throws {
        let feed = AnalyzerFakeFeed()
        let session = FakeSpeechSession()
        let source = AnalyzerSpeechSource(feed: feed, isAvailable: { true }, chooseLocale: { $0 },
                                          makeSession: { _ in session })
        let texts = LockedValue<[String]>([])
        try await source.start(locale: Locale(identifier: "de_DE"), hints: ["Hinweis"],
                               onText: { text in texts.mutate { $0.append(text) } },
                               onFailure: { _ in })
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(session.prepared, ["Hinweis"])
        let settled = await source.settle()
        XCTAssertEqual(settled, "Hallo Welt")
        source.stop()

        let unavailable = AnalyzerSpeechSource(feed: feed, isAvailable: { false },
                                               chooseLocale: { _ in nil },
                                               makeSession: { _ in session })
        do {
            try await unavailable.start(locale: Locale(identifier: "de_DE"), hints: [],
                                        onText: { _ in }, onFailure: { _ in })
            XCTFail("erwartet Fehler")
        } catch {}
        unavailable.stop()

        let failing = AnalyzerFakeFeed()
        failing.failure = APIError(message: "kaputt")
        let failingSource = AnalyzerSpeechSource(feed: failing, isAvailable: { true },
                                                 chooseLocale: { $0 }, makeSession: { _ in session })
        do {
            try await failingSource.start(locale: Locale(identifier: "de_DE"), hints: [],
                                          onText: { _ in }, onFailure: { _ in })
            XCTFail("erwartet Fehler")
        } catch {}
        failingSource.stop()

        let brokenSession = FakeSpeechSession()
        brokenSession.failure = APIError(message: "kaputt")
        let broken = AnalyzerSpeechSource(feed: feed, isAvailable: { true }, chooseLocale: { $0 },
                                          makeSession: { _ in brokenSession })
        do {
            try await broken.start(locale: Locale(identifier: "de_DE"), hints: [],
                                   onText: { _ in }, onFailure: { _ in })
            XCTFail("erwartet Fehler")
        } catch {}
        broken.stop()

        let finishBroken = FakeSpeechSession()
        finishBroken.finishFailure = APIError(message: "kaputt")
        let settling = AnalyzerSpeechSource(feed: feed, isAvailable: { true }, chooseLocale: { $0 },
                                            makeSession: { _ in finishBroken })
        try await settling.start(locale: Locale(identifier: "de_DE"), hints: [], onText: { _ in },
                                 onFailure: { _ in })
        _ = await settling.settle()
        settling.stop()
        XCTAssertGreaterThan(finishBroken.finished, 0)
    }

    func testSmokeTheAnalyzerFeedConvertsBuffers() {
        let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let feed = AnalyzerFeed(target: target)
        let source = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 1024)!
        buffer.frameLength = 1024
        _ = feed.converted(buffer)
        _ = feed.traceLine
        let (_, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let delivery = AnalyzerFeed.delivery(feed, into: continuation)
        let empty = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 16)!
        empty.frameLength = 0
        delivery(empty)
        _ = feed.converted(empty)
        _ = feed.traceLine
    }

    func testTheAnalyzerFeedKeepsTheSignalOfAVoiceProcessingChannelLayout() throws {
        let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let feed = AnalyzerFeed(target: target)
        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 9)!
        let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                   interleaved: false, channelLayout: layout)
        let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4800)!
        buffer.frameLength = 4800
        for channel in 0..<9 {
            for frame in 0..<4800 {
                buffer.floatChannelData![channel][frame] = channel == 0 ? 0.25 : 0
            }
        }
        let converted = try XCTUnwrap(feed.converted(buffer))
        XCTAssertGreaterThan(SpeechLevelBoost.peak(of: converted), 0.1)
    }

    func testSmokeTheLiveSessionAndFailurePaths() async throws {
        let feed = AnalyzerFakeFeed()
        let failing = FakeSpeechSession()
        failing.startFailure = APIError(message: "kein dienst")
        let source = AnalyzerSpeechSource(feed: feed, makeSession: { _ in failing })
        do {
            try await source.start(locale: Locale(identifier: "en_US"), hints: [], onText: { _ in },
                                   onFailure: { _ in })
        } catch {}
        source.stop()

        let session = LiveSpeechAnalysisSession(locale: Locale(identifier: "en_US"), reporting: [])
        do {
            let (input, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            let pieces = try await session.start(input: input)
            try await Task.sleep(for: .milliseconds(150))
            _ = pieces
            continuation.finish()
        } catch {}
        await session.cancel()
        _ = try? await session.finish()

        let brokenStream = FakeSpeechSession()
        brokenStream.streamFailure = APIError(message: "abgebrochen")
        let failures = LockedValue<[String]>([])
        let brokenSource = AnalyzerSpeechSource(feed: feed, isAvailable: { true }, chooseLocale: { $0 },
                                                makeSession: { _ in brokenStream })
        try await brokenSource.start(locale: Locale(identifier: "en_US"), hints: [],
                                     onText: { _ in }, onFailure: { message in failures.mutate { $0.append(message) } })
        try await Task.sleep(for: .milliseconds(300))
        brokenSource.stop()
    }

    func testSmokeTheLiveSessionAndAssetSeams() async {
        let transcriber = SpeechTranscriber(locale: Locale(identifier: "en_US"), transcriptionOptions: [],
                                            reportingOptions: [], attributeOptions: [])
        AnalyzerSpeechSource.assetStatus = { _ in .installed }
        try? await AnalyzerSpeechSource.installModel(for: transcriber)
        AnalyzerSpeechSource.assetStatus = { _ in .supported }
        AnalyzerSpeechSource.installationRequest = { _ in nil }
        try? await AnalyzerSpeechSource.installModel(for: transcriber)
        AnalyzerSpeechSource.assetStatus = { transcriber in
            await AssetInventory.status(forModules: [transcriber])
        }
        AnalyzerSpeechSource.installationRequest = { transcriber in
            try? await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        }
        _ = await AnalyzerSpeechSource.assetStatus(transcriber)
        _ = await AnalyzerSpeechSource.installationRequest(transcriber)

        AnalyzerSpeechSource.assetStatus = { _ in .installed }
        let session = LiveSpeechAnalysisSession(locale: Locale(identifier: "en_US"), reporting: [])
        do {
            let format = try await session.prepare(hints: [])
            let (input, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            let pieces = try await session.start(input: input)
            try await Task.sleep(for: .milliseconds(200))
            _ = pieces
            _ = format
            continuation.finish()
        } catch {}
        await session.cancel()
        _ = try? await session.finish()
        AnalyzerSpeechSource.assetStatus = { transcriber in
            await AssetInventory.status(forModules: [transcriber])
        }
    }
}
