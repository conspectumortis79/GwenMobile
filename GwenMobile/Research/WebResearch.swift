import GwenMobileKit
import Foundation

private struct FetchOutcome: Sendable {
    let index: Int
    let hit: WebHit?
    let failure: String?
    let status: Int?
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
        try await hitsWithReport(for: query, via: lookup).hits
    }

    func hitsWithReport(for query: String,
                        via lookup: @escaping @Sendable (String) async throws -> [URL] = {
                            try await WebSearch.searchURLs($0)
                        }) async throws -> WebResearchResult {
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
        var report = fetched.report
        report.used = usable.count
        flowMark("WEBHOLEN dauer_ms=\(msOf(started.duration(to: .now))) quellen=\(usable.count) "
                 + "fehler=\(fetched.failures.count) nicht_verwendet=\(report.sourceIssues.count)")
        return WebResearchResult(hits: usable, report: report)
    }

    func fetch(_ urls: [URL]) async
        -> (hits: [WebHit], failures: [String], report: WebSourceReport) {
        guard !urls.isEmpty else { return ([], [], WebSourceReport()) }
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
        let fetched = ordered.compactMap(\.hit)
        let hits = fetched.filter { !$0.risk.isBlocked }
        let failures = ordered.compactMap(\.failure)
        let issues: [WebSourceIssue] = ordered.compactMap { outcome in
            if let failure = outcome.failure {
                let kind: WebSourceIssue.Kind = outcome.status == 403 || failure.contains("HTTP 403")
                    ? .blocked : .unavailable
                return WebSourceIssue(kind: kind, domain: outcome.domain, reason: failure)
            }
            if let hit = outcome.hit, hit.risk.isBlocked {
                return WebSourceIssue(kind: .blocked, domain: hit.domain,
                                      reason: L.t("source_report_blocked_reason"))
            }
            return nil
        }
        let report = WebSourceReport(used: hits.count, issues: issues)
        flowMark("FETCH gesamt dauer_ms=\(msOf(started.duration(to: .now))) quellen=\(hits.count) "
                 + "nicht_verwendet=\(report.sourceIssues.count) fehler=\(failures.count)")
        return (hits, failures, report)
    }

    nonisolated private static func load(_ url: URL, index: Int) async -> FetchOutcome {
        let started = ContinuousClock.now
        let domain = WebSearch.domain(of: url)
        do {
            let hit = try await WebSearch.fetchText(url)
            return FetchOutcome(index: index, hit: hit, failure: nil, status: nil, domain: domain,
                                milliseconds: msOf(started.duration(to: .now)))
        } catch let error as APIError {
            return FetchOutcome(index: index, hit: nil, failure: error.message, status: error.status,
                                domain: domain, milliseconds: msOf(started.duration(to: .now)))
        } catch {
            return FetchOutcome(index: index, hit: nil, failure: error.localizedDescription, status: nil,
                                domain: domain, milliseconds: msOf(started.duration(to: .now)))
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
