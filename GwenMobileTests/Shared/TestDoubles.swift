@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AVFoundation
import XCTest
import GwenMobileKit

final class MemoryKeyStore: KeyStoring, @unchecked Sendable {
    private let values = LockedValue<[String: String]>([:])

    func read(account: String) -> KeychainRead {
        values.current[account].map(KeychainRead.value) ?? .absent
    }

    @discardableResult
    func save(_ value: String, account: String) -> Bool {
        values.mutate { $0[account] = value }
        return true
    }

    @discardableResult
    func delete(account: String) -> Bool {
        values.mutate { $0[account] = nil }
        return true
    }
}

@MainActor
final class TestAudioFeed: AudioFeeding, @unchecked Sendable {
    private let running = LockedValue(false)

    var isRunning: Bool { running.current }

    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        running.set(true)
    }

    func stop() {
        running.set(false)
    }
}

final class TestSpeechTask: SystemSpeechRecognizer.SpeechTasking {
    func cancel() {}
}

@MainActor
final class TestPriceChecker: PriceWatchChecking {
    var offers: [PriceWatchOffer?] = []
    var price: Double?
    private(set) var checks = 0

    init(price: Double? = nil) {
        self.price = price
    }

    func check(_ watch: PriceWatch, credentials: PriceWatchCredentials) async throws -> PriceWatchOffer? {
        checks += 1
        if let price {
            return PriceWatchOffer(price: price, currency: "EUR", shop: "Laden", product: watch.product)
        }
        return offers.isEmpty ? nil : offers.removeFirst()
    }
}

@MainActor
struct TestPriceLookup: PriceLooking {
    var results: [WebHit]
    var fails: Bool

    init(results: [WebHit] = [], fails: Bool = false) {
        self.results = results
        self.fails = fails
    }

    init(hits: [WebHit]) {
        self.init(results: hits)
    }

    func hits(for terms: [String], region: PriceRegion) async throws -> [WebHit] {
        if fails { throw APIError(message: L.t("web_no_results")) }
        return results
    }
}

@MainActor
final class TestSpotifyAuth: SpotifyAuthorizing {
    var configured = true
    var token: String? = "token"

    var isConfigured: Bool { configured }
    func accessToken() async -> String? { token }
}

@MainActor
final class TestSpotifyRemote: SpotifyRemoteControlling {
    var connected = false
    var playing = false
    var connectResult: Bool
    var playResult: Bool
    var performResult: Bool
    var wakeResult: Bool
    private(set) var performed: [MusicAction] = []

    init(succeeding: Bool = false) {
        connectResult = succeeding
        playResult = succeeding
        performResult = succeeding
        wakeResult = succeeding
    }

    var isConnected: Bool { connected }
    var isPlaying: Bool { playing }

    func connect(token: String) async -> Bool {
        connected = connectResult
        return connectResult
    }

    func play(uri: String) async -> Bool { playResult }

    func perform(_ action: MusicAction) async -> Bool {
        performed.append(action)
        return performResult
    }

    func wakeAndPlay(uri: String) async -> Bool { wakeResult }
}

struct TestSpotifyWeb: SpotifyWebControlling {
    var target: SpotifyTarget?
    var failing: Bool
    var result: SpotifyWebResult

    init(target: SpotifyTarget? = nil, failing: Bool = true, result: SpotifyWebResult = .done) {
        self.target = target
        self.failing = failing
        self.result = result
    }

    func find(_ request: MusicRequest, token: String) async throws -> SpotifyTarget? {
        if failing { throw APIError(message: "web kaputt") }
        return target
    }

    func play(_ target: SpotifyTarget?, token: String) async throws -> SpotifyWebResult {
        if failing { throw APIError(message: "web kaputt") }
        return result
    }

    func perform(_ action: MusicAction, token: String) async throws -> SpotifyWebResult {
        if failing { throw APIError(message: "web kaputt") }
        return result
    }
}
