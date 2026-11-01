@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation
import UIKit

extension DebugFeatureProbe {
    static func sourceTrust(_ view: ChatView) async {
        let report = SweepReport(file: "source_trust.txt")
        gate(report)
        feedback(report)
        dossier(report)
        review(report)
        network(report)
        await live(view, report)
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: report.content]],
                                      options: [.localOnly: true])
        flowLog.info("SOURCETRUST fertig")
    }

    private static func gate(_ report: SweepReport) {
        let cases: [(String, String, Bool)] = [
            ("normal", "https://www.spiegel.de/politik/x", false),
            ("benutzername", "https://user@example.org/a", false),
            ("ip_adresse", "https://93.184.216.34/a", false),
            ("nur_http", "http://example.org/a", false),
            ("punycode", "https://xn--mnchen-3ya.de/a", false),
            ("gemeldet", "https://example.org/a", true),
        ]
        for (name, address, reported) in cases {
            let verdict = SourceGuard.assess(URL(string: address), reported: reported)
            report.add("GATE_\(name)", "risiko=\(verdict.risk.rawValue) "
                       + "gruende=\(verdict.reasons.map(\.rawValue).joined(separator: ","))")
        }
        let name = "ProbeGate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let store = SourceReports(defaults: defaults, key: "reports")
        store.report("fake.test")
        let sourceGate = SourceGate(reports: store)
        let urls = [URL(string: "https://user@example.org/a")!, URL(string: "https://fake.test/a")!,
                    URL(string: "https://example.org/a")!]
        let allowed = urls.filter { !sourceGate.isBlocked($0) }
        defaults.removePersistentDomain(forName: name)
        report.add("GATE_FILTER", "vorher=\(urls.count) nachher=\(allowed.count) "
                   + "rest=\(allowed.compactMap(\.host).joined(separator: ","))")
    }

    private static func feedback(_ report: SweepReport) {
        let name = "ProbeReports.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let store = SourceReports(defaults: defaults, key: "reports")
        store.report("fake.test")
        let reported = store.isReported("FAKE.TEST")
        store.withdraw("fake.test")
        let withdrawn = !store.isReported("fake.test")
        defaults.removePersistentDomain(forName: name)
        report.add("MELDUNG", "gemeldet=\(reported) zurueckgenommen=\(withdrawn) "
                   + "anzahl=\(store.reportedDomains.count)")
    }

    private static func dossier(_ report: SweepReport) {
        let html = #"<meta property="article:published_time" content="2024-06-02T10:00:00Z"><meta name="author" content="Max Mustermann"><a href="/impressum">Impressum</a><script type="application/ld+json">{"@type":"NewsArticle"}</script>"#
        let parsed = SourceMetadata.from(html: html)
        report.add("DOSSIER_FELDER", "datum=\(parsed.published ?? "-") autor=\(parsed.author ?? "-") "
                   + "typen=\(parsed.kinds.joined(separator: ",")) "
                   + "impressum=\(parsed.imprint) werbung=\(parsed.paidLinks)")
        let risk = SourceGuard.Verdict(risk: .caution, reasons: [.punycode])
        report.add("DOSSIER_ZEILE", parsed.dossier(risk: risk))
        let empty = SourceMetadata()
        report.add("DOSSIER_LEER", empty.dossier(risk: SourceGuard.Verdict()))
    }

    private static func network(_ report: SweepReport) {
        let agency = "Der Bundestag hat am Mittwoch ein Gesetz beschlossen, das neue Gasheizungen ab 2027 "
            + "verbietet. Die Regelung gilt für Neubauten und sieht Übergangsfristen vor. Die Opposition "
            + "kritisierte den Zeitplan als zu knapp."
        let other = "Die Stadtwerke melden einen neuen Rekord bei der Solarstromerzeugung. Im dritten Quartal "
            + "stieg die Einspeisung deutlich. Ein Sprecher nannte die Zahlen erfreulich."
        let hits = [WebHit(title: "A", url: "https://a.test/x", domain: "a.test", text: agency),
                    WebHit(title: "B", url: "https://b.test/y", domain: "b.test", text: agency),
                    WebHit(title: "C", url: "https://c.test/z", domain: "c.test", text: other)]
        let copied = SourceReview.analyze(
            answer: "Der Bundestag hat das Gesetz beschlossen [1][2]. Die Stadtwerke melden einen Rekord [3].",
            hits: hits)
        report.add("SYNDIKATION", "quellen=\(hits.count) urspruenge=\(SourceSimilarity.independentGroups(hits).count) "
                   + "kopien=\(copied.copyCount) zitiert=\(copied.citedSources) "
                   + "zitat_urspruenge=\(copied.citedOrigins) doppelt=\(copied.citedDuplicates) "
                   + "quergelesen=\(copied.crossChecked) einzeln=\(copied.singleSource)")
        let single = SourceReview.analyze(answer: "Der Bundestag hat das Gesetz beschlossen [1][2].",
                                          hits: [hits[0], hits[1]])
        report.add("SYNDIKATION_EINZELN", "urspruenge=\(single.citedOrigins) "
                   + "doppelt=\(single.citedDuplicates) einzeln=\(single.singleSource)")
        report.add("SYNDIKATION_BLOCK", hits[1].sourceBlock(numbered: 2, copyOf: 1))
        let verdicts = SourceVerifier.parse(
            "{\"claims\":[{\"claim\":\"Nur Neubauten\",\"sources\":[1],\"verdict\":\"contradicted\","
            + "\"contradicts\":[3]}]}") ?? []
        let checked = copied.applying(verdicts)
        report.add("WIDERSPRUCH", "geparst=\(verdicts.count) widersprochen=\(checked.contradicted.count) "
                   + "unbelegt=\(checked.unsupported.count) verifiziert=\(checked.verified)")
    }

    private static func review(_ report: SweepReport) {
        let hits = [WebHit(title: "A", url: "https://a.test/x", domain: "a.test", text: "Text A"),
                    WebHit(title: "B", url: "https://b.test/y", domain: "b.test", text: "Text B")]
        let several = SourceReview.analyze(answer: "Berlin liegt an der Spree [1]. Die Zahl wächst [2].",
                                           hits: hits)
        report.add("PRUEFUNG_MEHRERE", "zitate=\(several.citedClaims) urspruenge=\(several.citedOrigins) "
                   + "quergelesen=\(several.crossChecked) einzelquelle=\(several.singleSource)")
        let one = SourceReview.analyze(answer: "Berlin liegt an der Spree [1]. Die Zahl wächst [1].",
                                       hits: [hits[0]])
        report.add("PRUEFUNG_EINZEL", "zitate=\(one.citedClaims) urspruenge=\(one.citedOrigins) "
                   + "einzelquelle=\(one.singleSource)")
        let note = SourceReview.coverageNote(hits: [hits[0],
                                                    WebHit(title: "C", url: "https://www.a.test/z",
                                                           domain: "www.a.test", text: "Text C")])
        report.add("EINZEL_WEBSEITE", "hinweis=\(note)")
        let parsed = SourceVerifier.parse(
            "{\"claims\":[{\"claim\":\"Berlin liegt an der Spree\",\"sources\":[1],\"supported\":false}]}")
        let checked = one.applying(parsed ?? [])
        report.add("PRUEFUNG_VERIFIER", "geparst=\(parsed?.count ?? -1) geprueft=\(checked.checkedClaims) "
                   + "unbelegt=\(checked.unsupported.count) verifiziert=\(checked.verified)")
    }

    @MainActor private static func live(_ view: ChatView, _ report: SweepReport) async {
        view.store.newConversation()
        let (sent, ms) = await answerAfterSend(view, "Wer hat den Eurovision Song Contest 2026 gewonnen?")
        let settled = await ProbeWait.until(120) { sent.map { !view.sourceChecks.contains($0.id) } ?? true }
        let answer = view.store.current?.messages.first { $0.id == sent?.id } ?? sent
        let review = answer?.sourceReview
        report.add("LIVE_ANTWORT", "ms=\(ms) zeichen=\(answer?.text.count ?? -1) "
                   + "quellen=\(answer?.sources?.count ?? -1) "
                   + "domains=\(answer?.sources?.map(\.domain).joined(separator: ",") ?? "-")")
        report.add("LIVE_PRUEFUNG", "abgeschlossen=\(settled) zitate=\(review?.citedClaims ?? -1) "
                   + "quellen=\(review?.citedSources ?? -1) "
                   + "urspruenge=\(review?.citedOrigins ?? -1) "
                   + "doppelt=\(review?.citedDuplicates ?? -1) "
                   + "kopien=\(review?.copyCount ?? -1) "
                   + "quergelesen=\(review?.crossChecked ?? false) "
                   + "einzelquelle=\(review?.singleSource ?? false) "
                   + "geprueft=\(review?.checkedClaims ?? -1) "
                   + "unbelegt=\(review?.unsupported.count ?? -1) "
                   + "widersprochen=\(review?.contradicted.count ?? -1) "
                   + "verifiziert=\(review?.verified ?? false)")
        report.add("LIVE_ANFANG", TextLine.oneLine(answer?.text ?? "", limit: 200))
    }
}
#endif
