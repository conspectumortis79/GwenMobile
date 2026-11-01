import GwenMobileKit
import Foundation

private struct FetchOutcome: Sendable {
    let index: Int
    let hit: WebHit?
    let failure: String?
    let domain: String
    let milliseconds: Int
}

@MainActor
struct WebResearch {
    static let minimumSourceCount = 1
    static let searchAttempts = 2
    static let searchRetryBackoff = Duration.seconds(3)
    static let fetchInFlight = 5

    private let onStatus: (String) -> Void

    init(onStatus: @escaping (String) -> Void) {
        self.onStatus = onStatus
    }

    func hits(for query: String,
              via lookup: @escaping @Sendable (String) async throws -> [URL] = {
                  try await WebSearch.searchURLs($0)
              }) async throws -> [WebHit] {
        let started = ContinuousClock.now
        let urls = try await searchedURLs(query, via: lookup)
        guard !urls.isEmpty else { throw APIError(message: L.t("web_no_results")) }
        let fetched = await fetch(urls)
        let usable = SearchShape.substantial(fetched.hits)
        guard usable.count >= Self.minimumSourceCount else {
            throw APIError(message: fetched.failures.isEmpty
                                ? L.t("web_no_results")
                                : L.fmt("web_all_fetches_failed", fetched.failures[0]))
        }
        flowMark("WEBHOLEN dauer_ms=\(msOf(started.duration(to: .now))) quellen=\(usable.count) "
                 + "fehler=\(fetched.failures.count)")
        return usable
    }

    func fetch(_ urls: [URL]) async -> (hits: [WebHit], failures: [String]) {
        guard !urls.isEmpty else { return ([], []) }
        let started = ContinuousClock.now
        var outcomes = [FetchOutcome?](repeating: nil, count: urls.count)
        var done = 0
        await withTaskGroup(of: FetchOutcome.self) { group in
            var launched = 0
            func launchNext() {
                let index = launched
                launched += 1
                let url = urls[index]
                group.addTask { await Self.load(url, index: index) }
            }
            while launched < min(urls.count, Self.fetchInFlight) {
                launchNext()
            }
            for await outcome in group {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                outcomes[outcome.index] = outcome
                done += 1
                onStatus("\(L.t("web_fetching")) (\(done)/\(urls.count)) \(outcome.domain)")
                if let hit = outcome.hit {
                    flowMark("FETCH dauer_ms=\(outcome.milliseconds) zeichen=\(hit.text.count) "
                             + "domain=\(outcome.domain)")
                } else {
                    flowMark("FETCH fehlgeschlagen dauer_ms=\(outcome.milliseconds) "
                             + "domain=\(outcome.domain)")
                }
                guard launched < urls.count else { continue }
                launchNext()
            }
        }
        let ordered = outcomes.compactMap { $0 }
        let hits = ordered.compactMap(\.hit)
        let failures = ordered.compactMap(\.failure)
        flowMark("FETCH gesamt dauer_ms=\(msOf(started.duration(to: .now))) quellen=\(hits.count) "
                 + "fehler=\(failures.count)")
        return (hits, failures)
    }

    nonisolated private static func load(_ url: URL, index: Int) async -> FetchOutcome {
        let started = ContinuousClock.now
        let domain = WebSearch.domain(of: url)
        do {
            let hit = try await WebSearch.fetchText(url)
            return FetchOutcome(index: index, hit: hit, failure: nil, domain: domain,
                                milliseconds: msOf(started.duration(to: .now)))
        } catch let error as APIError {
            return FetchOutcome(index: index, hit: nil, failure: error.message, domain: domain,
                                milliseconds: msOf(started.duration(to: .now)))
        } catch {
            return FetchOutcome(index: index, hit: nil, failure: error.localizedDescription, domain: domain,
                                milliseconds: msOf(started.duration(to: .now)))
        }
    }

    func searchedURLs(_ query: String,
                      attempts: Int = searchAttempts,
                      backoff: Duration = searchRetryBackoff,
                      via lookup: @escaping @Sendable (String) async throws -> [URL]) async throws -> [URL] {
        var attempt = 1
        while true {
            let started = ContinuousClock.now
            let urls = try await Offload.run { try await lookup(query) }
            flowMark("SUCHE dauer_ms=\(msOf(started.duration(to: .now))) urls=\(urls.count) "
                     + "versuch=\(attempt)")
            if !urls.isEmpty { return urls }
            guard attempt < max(1, attempts) else {
                flowMark("SUCHE leer versuch=\(attempt) endgültig")
                return []
            }
            flowMark("SUCHE leer versuch=\(attempt) erneut")
            onStatus(L.t("web_searching_again"))
            try await Task.sleep(for: backoff)
            attempt += 1
        }
    }

    static func sources(from hits: [WebHit]) -> [WebSource] {
        hits.map { WebSource(title: $0.title, url: $0.url, domain: $0.domain) }
    }
}
