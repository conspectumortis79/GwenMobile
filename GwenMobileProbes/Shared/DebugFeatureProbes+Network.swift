@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

extension DebugFeatureProbe {
    static func retryProbe() async {
        let report = SweepReport(file: "search_retry.txt")
        var statuses: [String] = []
        let emptyCalls = LockedValue(0)
        let started = ContinuousClock.now
        let urls = try? await WebResearch(onStatus: { statuses.append($0) })
            .searchedURLs("gwenmobile-suchtest", attempts: 2, backoff: .seconds(3)) { _ in
                emptyCalls.mutate { stored in stored += 1 }
                return []
            }
        report.add("LEERE_SUCHE", "versuche=\(emptyCalls.current) urls=\(urls?.count ?? -1) "
                   + "ms=\(msOf(started.duration(to: .now))) kapseln=\(statuses.joined(separator: "|"))")
        let lateCalls = LockedValue(0)
        let recovered = try? await WebResearch(onStatus: { _ in })
            .searchedURLs("gwenmobile-suchtest", attempts: 2, backoff: .seconds(3)) { _ in
                let attempt = lateCalls.mutate { stored in stored += 1; return stored }
                return attempt == 1 ? [] : [URL(string: "https://de.wikipedia.org/x")!]
            }
        report.add("ERHOLTE_SUCHE", "versuche=\(lateCalls.current) urls=\(recovered?.count ?? -1)")
        let failingCalls = LockedValue(0)
        do {
            _ = try await WebResearch(onStatus: { _ in })
                .searchedURLs("gwenmobile-suchtest", attempts: 3, backoff: .seconds(3)) { _ in
                    failingCalls.mutate { stored in stored += 1 }
                    throw APIError(message: "HTTP 503")
                }
            report.add("TRANSPORTFEHLER", "versuche=\(failingCalls.current) ende=kein Fehler")
        } catch {
            report.add("TRANSPORTFEHLER", "versuche=\(failingCalls.current) ende=\(error.localizedDescription.prefix(40))")
        }
        flowLog.info("SUCHRETRY fertig")
    }

    static func tlsRetry() async {
        let report = SweepReport(file: "tls_retry.txt")
        for (name, base) in [("zertifikat_abgelaufen", "https://expired.badssl.com/compatible-mode/v1"),
                             ("host_unbekannt", "https://gwenmobile-nicht-vorhanden.invalid/v1")] {
            let started = ContinuousClock.now
            var chunks = 0
            do {
                let req = try QwenAPI.makeRequest(baseURL: base, key: "sk-test",
                                                  model: "qwen3.8-flash",
                                                  messages: [ChatMessage(role: .user, text: "x")],
                                                  imageData: [], thinking: .nothing)
                for try await chunk in QwenAPI.streamText(req: req) {
                    chunks += chunk.count
                }
                report.add("TLSRETRY_\(name)", "durchgekommen=ja zeichen=\(chunks) "
                           + "ms=\(msOf(started.duration(to: .now)))")
            } catch {
                report.add("TLSRETRY_\(name)", "zeichen=\(chunks) ms=\(msOf(started.duration(to: .now))) "
                           + "code=\((error as NSError).code) text=\(String(error.localizedDescription.prefix(70)))")
            }
        }
        flowLog.info("TLSRETRY fertig")
    }

    @MainActor static func webProbe(_ view: ChatView, reportFile: String, label: String,
                                            question: String,
                                            findings: (ChatMessage?, Int) -> String) async {
        let report = SweepReport(file: reportFile)
        view.store.newConversation()
        let (answer, ms) = await answerAfterSend(view, question)
        report.add(label, findings(answer, ms))
        report.add("\(label)_KAPSEL", "danach=\(view.webStatus ?? "nil")")
        flowLog.info("\(label) fertig")
    }

    static func webAsk(_ view: ChatView) async {
        await webProbe(view, reportFile: "web_ask.txt", label: "WEBASK",
                       question: "bitte aktuelle nachrichten aus berlin") { answer, ms in
            "ms=\(ms) zeichen=\(answer?.text.count ?? -1) "
            + "quellen=\(answer?.sources?.count ?? -1) "
            + "domains=\(answer?.sources?.map(\.domain).joined(separator: ",") ?? "-") "
            + "anfang=\(TextLine.oneLine(answer?.text ?? "", limit: 160))"
        }
    }

    @MainActor static func newsVerify(_ view: ChatView) async {
        let report = SweepReport(file: "news_verify.txt")
        let before = view.settings.research.verifySources
        view.settings.research.verifySources = true
        view.store.newConversation()
        let (answer, ms) = await answerAfterSend(view, "Bitte die aktuellen Nachrichten für Berlin")
        let messageID = answer?.id
        let deadline = ContinuousClock.now + .seconds(90)
        while ContinuousClock.now < deadline, let id = messageID, view.probeSourceChecks.contains(id) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        let fresh = view.store.current?.messages.last { $0.id == messageID }
        let review = fresh?.sourceReview
        let pending = messageID.map { view.probeSourceChecks.contains($0) } ?? false
        report.add("NEWSVERIFY", "ms=\(ms) antwort=\(answer != nil) quellen=\(fresh?.sources?.count ?? -1) "
                   + "review=\(review != nil) offen=\(pending)")
        if let review {
            let independent = review.citedDuplicates > 0 || review.singleSource || review.crossChecked
                || (review.citedClaims == 0 && review.sourceDomains > 0)
            report.add("REVIEW", "verified=\(review.verified) zitate=\(review.citedClaims) "
                       + "geprueft=\(review.checkedClaims) cross=\(review.crossChecked) "
                       + "einzelquelle=\(review.singleSource) ergebnisse=\(review.results.count) "
                       + "unbelegt=\(review.unsupported.count) widersprochen=\(review.contradicted.count)")
            report.add("ANZEIGE", "pruefzeile=\(review.verified) unabhaengig=\(independent)")
        }
        view.settings.research.verifySources = before
        flowLog.info("NEWSVERIFY fertig")
    }

    @MainActor static func reviewMissing(_ view: ChatView) async {
        let report = SweepReport(file: "review_missing.txt")
        let hits = [WebHit(title: "Stadtwerke", url: "https://stadtwerke.test/rekord",
                           domain: "stadtwerke.test",
                           text: "Die Stadtwerke melden einen neuen Rekord bei der Solarstromerzeugung."),
                    WebHit(title: "Zeitung", url: "https://zeitung.test/stadt",
                           domain: "zeitung.test",
                           text: "Im dritten Quartal stieg die Einspeisung deutlich.")]
        let answer = "Die Stadtwerke melden einen Rekord bei der Solarstromerzeugung [1]. "
            + "Die Einspeisung stieg im dritten Quartal deutlich [2]."
        let review = SourceReview.analyze(answer: answer, hits: hits)
        view.store.newConversation()
        guard let id = view.store.currentID else { return }
        view.store.appendAssistant(answer, model: "Probe", elapsed: 1, to: id,
                                   sources: WebResearch.sources(from: hits), sourceReview: review)
        report.add("REVIEWMISSING", "verified=\(review.verified) zitate=\(review.citedClaims) "
                   + "fehlt=\(review.verificationMissing) unabhaengig=\(review.crossChecked)")
        try? await Task.sleep(for: .milliseconds(2500))
        flowLog.info("REVIEWMISSING fertig")
    }

}
#endif
