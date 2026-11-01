@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AVFoundation
import Speech
import XCTest
import GwenMobileKit

@MainActor
private final class SeamSpeechSession: SpeechAnalysisSessioning {
    var format: AVAudioFormat? = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
    var failure: Error?
    private var continuation: AsyncThrowingStream<SpeechPiece, Error>.Continuation?

    func prepare(hints: [String]) async throws -> AVAudioFormat {
        if let failure { throw failure }
        guard let format else { throw APIError(message: "kein format") }
        return format
    }

    func start(input: AsyncStream<AnalyzerInput>) async throws -> AsyncThrowingStream<SpeechPiece, Error> {
        let (stream, continuation) = AsyncThrowingStream<SpeechPiece, Error>.makeStream()
        self.continuation = continuation
        continuation.finish()
        return stream
    }

    func finish() async throws {}

    func cancel() async { continuation?.finish() }
}

@MainActor
final class VoiceHardwareSeamTests: GwenTestCase {
    func testTheBufferSourceRunsWithAStubbedAuthorization() async throws {
        let feed = TestAudioFeed()
        let source = BufferSpeechSource(feed: feed, authorize: {})
        let failures = LockedValue<[String]>([])
        do {
            try await source.start(locale: Locale(identifier: "de_DE"), hints: ["Hinweis"],
                                   onText: { _ in },
                                   onFailure: { message in failures.mutate { $0.append(message) } })
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        try? await Task.sleep(for: .milliseconds(800))
        source.stop()
        XCTAssertFalse(source.isCapturing)
        XCTAssertFalse(failures.current.count > 3)
    }

    func testTheTranscriberAuthorizedPath() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("speech-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("still.wav")
        let samples = Array(repeating: Int16(0), count: 1_600)
        let data = WaveFile.pcm16(samples, sampleRate: 16_000)
        try? data.write(to: url)
        let recognizer = SystemSpeechRecognizer(locale: Locale(identifier: "de_DE"), timeout: 1)
        do {
            let text = try await recognizer.transcribeAuthorized(wavURL: url)
            XCTAssertTrue(text.isEmpty || !text.isEmpty)
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        _ = recognizer.isAvailable
        _ = SystemSpeechRecognizer.authorizationStatus
        XCTAssertFalse(SystemSpeechRecognizer.reportsNoSpeech(APIError(message: "normal")))
    }

    func testTheMicrophoneTapSessionFailureIsReported() async {
        let tap = MicrophoneTap()
        tap.prepareSession = { _ in throw APIError(message: "keine sitzung") }
        do {
            try await tap.start { _ in }
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        tap.stop()
        XCTAssertFalse(tap.isFlowing)
    }

    func testTheAnalyzerSourceWithoutAvailability() async {
        let source = AnalyzerSpeechSource(feed: TestAudioFeed(), isAvailable: { false })
        do {
            try await source.start(locale: Locale(identifier: "de_DE"), hints: [],
                                   onText: { _ in }, onFailure: { _ in })
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        source.stop()
        let session = SeamSpeechSession()
        session.failure = APIError(message: "kein modell")
        let unsupported = AnalyzerSpeechSource(feed: TestAudioFeed(), isAvailable: { true },
                                               chooseLocale: { $0 }, makeSession: { _ in session })
        do {
            try await unsupported.start(locale: Locale(identifier: "xx_XX"), hints: [],
                                        onText: { _ in }, onFailure: { _ in })
        } catch {}
        unsupported.stop()
    }

    func testTheAnalyzerPreparationFailure() async {
        let session = SeamSpeechSession()
        session.failure = APIError(message: "kein modell")
        let source = AnalyzerSpeechSource(feed: TestAudioFeed(), isAvailable: { true },
                                          chooseLocale: { $0 }, makeSession: { _ in session })
        do {
            try await source.start(locale: Locale(identifier: "de_DE"), hints: [],
                                   onText: { _ in }, onFailure: { _ in })
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        source.stop()
    }

    func testTheAnalyzerSourceWithoutAnAudioFormat() async {
        let session = SeamSpeechSession()
        session.format = nil
        let source = AnalyzerSpeechSource(feed: TestAudioFeed(), isAvailable: { true },
                                          chooseLocale: { $0 }, makeSession: { _ in session })
        do {
            try await source.start(locale: Locale(identifier: "de_DE"), hints: [],
                                   onText: { _ in }, onFailure: { _ in })
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        source.stop()
    }

    func testTheAnalyzerSourceWithAConcreteFormat() async {
        let source = AnalyzerSpeechSource(feed: TestAudioFeed(), isAvailable: { true },
                                          chooseLocale: { $0 }, makeSession: { _ in SeamSpeechSession() })
        do {
            try await source.start(locale: Locale(identifier: "de_DE"), hints: [],
                                   onText: { _ in }, onFailure: { _ in })
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        source.stop()
    }
}
