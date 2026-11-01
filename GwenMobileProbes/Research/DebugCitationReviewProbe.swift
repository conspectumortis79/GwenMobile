@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugCitationReviewProbe {
    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "citation_review.txt")
        deterministic(report)
        await live(view, report)
        flowLog.info("CITATIONREVIEW fertig")
    }

    private static func deterministic(_ report: SweepReport) {
        let hits = [WebHit(title: "A", url: "https://a.test/x", domain: "a.test", text: "Text A"),
                    WebHit(title: "B", url: "https://b.test/y", domain: "b.test", text: "Text B")]
        let answer = "- Aus Musterstadt: Stadtlauf am Sonntag, 11. Mai 2026 [1]; neuer Platz im Ort [1]. "
            + "Quelle [1] nennt kein Datum."
        var review = SourceReview.analyze(answer: answer, hits: hits)
        review = review.applying([
            SourceReview.Claim(claim: "Zu „Beispielstadt“ findet sich in keiner Quelle etwas",
                               sources: [], verdict: .unsupported),
            SourceReview.Claim(claim: "Quelle [1] nennt kein Datum.", sources: [1], verdict: .unsupported),
        ])
        let marked = review.marks(in: answer).map { String(answer[$0.range]) }
        report.add("OHNE_QUELLE", "geprueft=\(review.checkedClaims) behalten=\(review.results.count == 2) "
                   + "unbelegt=\(review.unsupported.count) warnungen=\(review.warnings.map(\.claim).joined(separator: " | "))")
        report.add("SATZMARKE", "markierungen=\(marked.count) bereiche=\(marked.joined(separator: " || "))")
    }

    private static func live(_ view: ChatView, _ report: SweepReport) async {
        guard view.settings.isConfigured else {
            report.add("LIVE_ABBRUCH", "kein schluessel konfiguriert")
            return
        }
        let hits = [WebHit(title: "Rekord", url: "https://stadtwerke.test/rekord", domain: "stadtwerke.test",
                           text: "Die Stadtwerke melden einen neuen Rekord bei der Solarstromerzeugung. "
                               + "Im dritten Quartal stieg die Einspeisung deutlich. Ein Sprecher nannte "
                               + "die Zahlen erfreulich.")]
        let answer = "Die Stadtwerke melden einen Rekord bei der Solarstromerzeugung [1]. "
            + "Quelle [1] nennt allerdings kein Datum."
        let review = SourceReview.analyze(answer: answer, hits: hits)
        let model = view.settings.answeringModel(hasPictures: false)
        let baseURL = view.settings.baseURL
        let key = view.settings.apiKey
        let thinking = view.settings.thinkingOffDirective(for: model)
        do {
            let request = try await Offload.run {
                try SourceVerifier.makeRequest(baseURL: baseURL, key: key, model: model,
                                               answer: answer, hits: hits, thinking: thinking)
            }
            guard let raw = try await QwenAPI.askText(request),
                  let parsed = SourceVerifier.parse(raw) else {
                report.add("LIVE_META", "keine verwertbare antwort")
                return
            }
            let uncited = parsed.filter { !($0.sources ?? []).contains { $0 >= 1 } }
            let checked = review.applying(parsed)
            report.add("LIVE_ROH", "urteile=\(parsed.count) ohne_quelle=\(uncited.count)")
            report.add("LIVE_META", "geprueft=\(checked.checkedClaims) unbelegt=\(checked.unsupported.count) "
                       + "widersprochen=\(checked.contradicted.count) "
                       + "urteile=\(checked.results.map { "\($0.verdict.rawValue):\($0.claim)" }.joined(separator: " | "))")
        } catch {
            report.addFailure("LIVE_META", error)
        }
    }
}
#endif
