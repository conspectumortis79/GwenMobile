@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import GwenMobileKit
import AVFoundation
import XCTest

@MainActor
final class SourceLineGapTests: GwenTestCase {
    func testTheWebSearchEmptyPageAndResearchFailures() async {
        MockHTTP.install { _ in (200, Data("<html><body></body></html>".utf8)) }
        do {
            _ = try await WebSearch.fetchText(URL(string: "https://leer.test/a")!)
            XCTFail("erwartet Fehler")
        } catch {}
        MockHTTP.uninstall()
        MockHTTP.failWith { _ in URLError(.cannotConnectToHost) }
        MockHTTP.install { _ in (200, Data()) }
        let research = WebResearch(onStatus: { _ in })
        _ = await research.fetch([URL(string: "https://weg.test/a")!])
        let urls = try? await research.searchedURLs("Test", attempts: 1, backoff: .milliseconds(1),
                                                    via: { _ in [] })
        XCTAssertEqual(urls?.count, 0)
        MockHTTP.uninstall()
    }

    func testThePictureSearchAndMetadataEdges() async {
        do {
            _ = try BingPictureSearch.request(query: "", offset: 0)
            XCTFail("erwartet Fehler")
        } catch {}
        _ = SourceMetadata.from(html: #"<script type="application/ld+json">"kaputt"</script>"#)
        _ = SourceMetadata.from(html: #"<script type="application/ld+json">[1,2]</script>"#)
    }

    func testSmokeTheSpotifyWebEdge() async {
        let client = SpotifyWebClient(send: { _ in (Data(), 500) })
        _ = try? await client.find(MusicRequest(action: .play, query: "x"), token: "t")
    }
}

@MainActor
private final class GapFailingFeed: ResumableAudioFeeding {
    var isRunning: Bool { false }
    var isFlowing: Bool { false }
    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        throw APIError(message: "kein mikrofon")
    }
    func stop() {}
    func resume() async throws {}
    func reconnect() async throws {}
}

@MainActor
extension SourceLineGapTests {
    func testTheRateLimitAndITunesEdges() async {
        let failed: Void? = try? await RateLimitRetry.run(attempts: 1, backoff: .milliseconds(1)) {
            throw APIError(message: "kaputt")
        }
        XCTAssertNil(failed)
        let catalog = ITunesCatalogSearch(country: "DE", fetch: { _ in Data("{\"results\":[]}".utf8) })
        let found = try? await catalog.find(MusicRequest(action: .play, query: "Nix", kind: .album))
        XCTAssertNil(found)
    }

    func testTheWeatherAndResearchFailureLines() async {
        var service = WeatherService()
        WeatherService.clearCache()
        service.fetcher = { _ in Data("{}".utf8) }
        let place = WeatherPlace(name: "Insel-\(UUID().uuidString)", latitude: 1, longitude: 2,
                                 timezone: nil)
        do {
            _ = try await service.day(place: place, date: "2026-10-05")
            XCTFail("erwartet Fehler")
        } catch {}
        MockHTTP.install { _ in (200, Data("<html><body></body></html>".utf8)) }
        do {
            _ = try await WebSearch.fetchText(URL(string: "https://leer.test/b")!)
            XCTFail("erwartet Fehler")
        } catch {}
        MockHTTP.uninstall()
    }

    func testTheHeldMicrophoneFailureAndBriefingStub() async {
        let mic = HeldMicrophone(tap: GapFailingFeed(), disruptions: StubDisruptions(),
                                 headsets: StubHeadsets())
        do {
            try await mic.start { _ in }
            XCTFail("erwartet Fehler")
        } catch {}
        let travel = await StubBriefingTravel().briefingTravel(to: "Ort", departure: Date())
        XCTAssertNil(travel)
    }

    func testTheVoiceCatalogAndRouterStubs() async {
        if let voice = AVSpeechSynthesisVoice.speechVoices().first {
            _ = VoiceCatalog.voice(identifier: voice.identifier, language: .de)
        }
        let ask = RouterAsk(baseURL: "https://x.test", key: "k", model: "m", text: "Hallo",
                            context: SendContext(), history: [], thinking: .nothing)
        let steps = await StubRouterSteps().steps(ask)
        XCTAssertEqual(steps.map(\.route), [.chat])
    }
}

@MainActor
extension SourceLineGapTests {
    func testTheRemainingSourceEdges() async {
        let web = SpotifyWebClient(send: { _ in (Data(), 500) })
        _ = try? await web.play(nil, token: "t")
        _ = RichTextFile.pictures(in: Data("kein bild".utf8))
        let catalog = ITunesCatalogSearch(country: "DE", fetch: { _ in Data("{\"results\":[]}".utf8) })
        _ = try? await catalog.find(MusicRequest(action: .play, query: "", kind: .album))
        _ = await OpenAIThinkingProbe.capabilities(baseURL: "", key: "", model: "")
        MockHTTP.failWith { _ in URLError(.badServerResponse) }
        MockHTTP.install { _ in nil }
        MockHTTP.uninstall()
        MockHTTP.install { _ in (200, Data("<html><body><p>x</p></body></html>".utf8)) }
        do {
            _ = try await WebSearch.fetchText(URL(string: "https://kurz.test/c")!)
            XCTFail("erwartet Fehler")
        } catch {}
        MockHTTP.uninstall()
        _ = SourceMetadata.from(html: #"<script type="application/ld+json">"foo"</script>"#)
    }
}

@MainActor
extension SourceLineGapTests {
    func testTheSpotifyWebFailureAndMetadataEntities() async {
        let source = SpotifySource(auth: TestSpotifyAuth(), remote: TestSpotifyRemote(),
                                   web: TestSpotifyWeb(), isActive: { false })
        let outcome = await source.play(MusicRequest(action: .play, query: "x"))
        guard case .failed = outcome else {
            XCTFail("erwartet Fehler")
            return
        }
        XCTAssertEqual(SourceMetadata.entities(in: "foo").count, 0)
        XCTAssertEqual(SourceMetadata.entities(in: [1, 2]).count, 0)
    }

    func testTheTranslationFallbackAndStreamFailure() async {
        OnDeviceTranslation.statusOverride = { _ in .ready }
        let batch = OnDeviceTranslation.batch
        OnDeviceTranslation.batch = { _, _, _ in throw TranslationProblem.unsupportedPair("fr") }
        defer {
            OnDeviceTranslation.batch = batch
            OnDeviceTranslation.statusOverride = nil
        }
        MockHTTP.install { _ in
            (200, ToolCallPayload.call(ToolRouter.reportTranslationTool, ["translation": "Bonjour"]))
        }
        defer { MockHTTP.uninstall() }
        let result = try? await TranslationFlow.run(TranslationJob(text: "Hallo", targetCode: "fr"),
                                                    credentials: TranslationCredentials(
                                                        baseURL: "https://api.test/v1", apiKey: "k",
                                                        model: "m", thinking: .nothing))
        XCTAssertEqual(result?.text, "Bonjour")
        MockHTTP.failWith { _ in URLError(.badServerResponse) }
        MockHTTP.install { _ in nil }
        let stream = QwenAPI.streamText(req: URLRequest(url: URL(string: "https://x.test")!))
        do {
            for try await _ in stream {}
        } catch {}
    }
}

@MainActor
private final class GapPriceChecker: PriceWatchChecking {
    func check(_ watch: PriceWatch, credentials: PriceWatchCredentials) async throws -> PriceWatchOffer? {
        nil
    }
}

@MainActor
private final class GapPriceNotifier: PriceWatchNotifying {
    func notify(_ watch: PriceWatch, offer: PriceWatchOffer) async -> Bool { true }
    func prepare() {}
}

@MainActor
private final class GapCancelSource: FinalizingTranscribing {
    let label = "gap"
    private(set) var isCapturing = false
    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        isCapturing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            onText("abbrechen")
        }
    }
    func stop() { isCapturing = false }
    func settle() async -> String? { nil }
}

@MainActor
extension SourceLineGapTests {
    func testTheLastHelpers() async {
        XCTAssertNil(RichTextFile.firstIndex(of: 9, in: [1, 2], from: 0))
        XCTAssertEqual(RichTextFile.firstIndex(of: 2, in: [1, 2], from: 0), 1)
        let store = PriceWatchStore(paths: temporaryPaths("gap-update"))
        let runner = PriceWatchFlowRunner(store: store, checker: GapPriceChecker(),
                                          credentials: PriceWatchCredentials(
                                            baseURL: "https://api.test/v1", key: "k", model: "m",
                                            thinking: .nothing),
                                          notifier: GapPriceNotifier())
        let outcome = await runner.run(PriceWatchRequest(action: .update, terms: ["Nix"], goal: 100),
                                       question: "frage")
        XCTAssertFalse(outcome.text.isEmpty)
        let value = try? await RateLimitRetry.run(attempts: 1, backoff: .milliseconds(1)) { 42 }
        XCTAssertEqual(value, 42)
        let voice = VoiceTranscriber(makeSource: { GapCancelSource() }, microphoneAllowed: { true })
        voice.signals = VoiceSignals(wake: "", stop: "senden", cancel: "abbrechen")
        voice.start { _ in }
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(voice.state, .idle)
    }
}

@MainActor
private final class GapPlayFailWeb: SpotifyWebControlling {
    private let target = SpotifyTarget(uri: "spotify:track:1",
                                       pick: MusicPick(kind: .song, name: "Lied"))
    func find(_ request: MusicRequest, token: String) async throws -> SpotifyTarget? { target }
    func play(_ target: SpotifyTarget?, token: String) async throws -> SpotifyWebResult {
        throw APIError(message: "play kaputt")
    }
    func perform(_ action: MusicAction, token: String) async throws -> SpotifyWebResult {
        throw APIError(message: "play kaputt")
    }
}

@MainActor
extension SourceLineGapTests {
    func testTheSpotifyPlayFailureAndPriceComparison() async {
        let source = SpotifySource(auth: TestSpotifyAuth(), remote: TestSpotifyRemote(),
                                   web: GapPlayFailWeb(), isActive: { false })
        let outcome = await source.play(MusicRequest(action: .play, query: "Lied"))
        guard case .failed = outcome else {
            XCTFail("erwartet Fehler")
            return
        }
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("duckduckgo") || url.contains("search") {
                let html = #"<a class="result__a" href="https://shop.test/a">Shop</a>"#
                return (200, Data(html.utf8))
            }
            return (500, Data())
        }
        defer { MockHTTP.uninstall() }
        let lookup = WebPriceLookup(onStatus: { _ in })
        do {
            _ = try await lookup.hits(for: ["PS5"], region: PriceRegion.device())
            XCTFail("erwartet Fehler")
        } catch {}
    }

    func testTheSourceReviewBestSentence() {
        var review = SourceReview()
        review.results = [SourceReview.ClaimResult(claim: "neun Millionen Einwohner",
                                                   verdict: .unsupported, sources: [2])]
        let marks = review.marks(in: "- Berlin liegt an der Spree [1]. Berlin hat neun Millionen Einwohner [2].")
        XCTAssertFalse(marks.isEmpty)
    }
}

@MainActor
private final class GapSlowCancelSource: FinalizingTranscribing {
    let label = "gap-slow"
    private(set) var isCapturing = false
    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        isCapturing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            onText("abbrechen")
        }
    }
    func stop() { isCapturing = false }
    func settle() async -> String? { nil }
}

@MainActor
extension SourceLineGapTests {
    func testTheDiscardVerdictAndSecondBestSentence() async {
        let voice = VoiceTranscriber(makeSource: { GapSlowCancelSource() },
                                     microphoneAllowed: { true })
        voice.signals = VoiceSignals(wake: "", stop: "senden", cancel: "abbrechen")
        voice.timing = VoiceTiming(silence: 0.05, nothingSaid: 2, maximum: 5)
        voice.start { _ in }
        try? await Task.sleep(for: .milliseconds(500))
        voice.stopAndTranscribe()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(voice.state, .idle)
        var review = SourceReview()
        review.results = [SourceReview.ClaimResult(
            claim: "Berlin liegt an der Spree und hat neun Millionen Einwohner",
            verdict: .unsupported, sources: [2])]
        let answer = "Berlin liegt an der Spree und hat neun. Berlin liegt an der Spree und hat neun Millionen."
        let span = SourceReview.CitedSpan(text: answer, range: answer.startIndex..<answer.endIndex,
                                          numbers: [1, 2])
        let result = SourceReview.ClaimResult(
            claim: "Berlin Spree neun Millionen", verdict: .unsupported, sources: [2])
        let range = SourceReview.sentenceMatch(result, in: span, answer: answer)
        XCTAssertNotNil(range)
        let marks = review.marks(
            in: "- Berlin liegt an der Spree [1]. Berlin liegt an der Spree und hat neun Millionen Einwohner [2].")
        XCTAssertFalse(marks.isEmpty)
    }
}

@MainActor
private final class GapManualSource: FinalizingTranscribing {
    let label = "manual"
    private(set) var isCapturing = false
    private var onText: (@MainActor (String) -> Void)?
    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        isCapturing = true
        self.onText = onText
    }
    func emit(_ text: String) { onText?(text) }
    func stop() { isCapturing = false }
    func settle() async -> String? { "abbrechen" }
}

@MainActor
extension SourceLineGapTests {
    func testTheManualDiscardVerdict() async {
        let source = GapManualSource()
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true })
        voice.signals = VoiceSignals(wake: "", stop: "senden", cancel: "abbrechen")
        XCTAssertEqual(VoiceCommand.verdict(for: "abbrechen", signals: voice.signals), .discard)
        voice.start { _ in }
        for _ in 0..<20 where voice.state != .recording {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(voice.state, .recording)
        source.emit("abbrechen")
        voice.stopAndTranscribe()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(voice.state, .idle)
    }
}
