@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugSourceCheckProbe {
    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "source_check_bg.txt")
        let savedVerify = view.settings.research.verifySources
        view.settings.research.verifySources = true
        defer { view.settings.research.verifySources = savedVerify }
        mechanism(view, report)
        await live(view, report)
        flowLog.info("SOURCEBG fertig")
    }

    private static func mechanism(_ view: ChatView, _ report: SweepReport) {
        report.add("ZITAT_NICHT_ASCII", CitationMarkers.shifted("A [١] B [2]", by: 1, sources: 2))
        let source = WebSource(title: "A", url: "https://a.test/x", domain: "a.test")
        let review = SourceReview(sourceDomains: 1, citedClaims: 1,
                                  checkedClaims: 1, unsupported: ["Nicht belegte Aussage"], verified: true)

        view.store.newConversation()
        if let convID = view.store.currentID {
            let text = "Berlin liegt an der Spree [1]."
            let placement = view.finishAnswer(text, artifacts: AnswerArtifacts(sources: [source]),
                                              model: "probe", convID: convID, started: Date(),
                                              announce: false)
            let messageID = placement?.messageID
            let before = view.store.current?.messages.last
            let applied = placement?.applySourceReview(review, to: view.store) ?? false
            let after = view.store.current?.messages.last
            report.add("MECHANIK_DIREKT", "nachricht=\(messageID?.uuidString.prefix(8) ?? "-") "
                       + "eingetragen=\(applied) gleiche_nachricht=\(after?.id == messageID) "
                       + "text_unveraendert=\(after?.text == before?.text) "
                       + "review=\(after?.sourceReview?.verified ?? false) "
                       + "nachrichten=\(view.store.current?.messages.count ?? -1)")
            _ = view.store.removeConversation(convID)
        } else {
            report.add("MECHANIK_DIREKT", "keine unterhaltung")
        }

        view.store.newConversation()
        if let convID = view.store.currentID {
            let started = Date()
            let writer = ChainMessageWriter()
            let slot = AnswerSlot(writer: writer)
            let placement = view.finishAnswer("Erster Ketten-Schritt [1].",
                                              artifacts: AnswerArtifacts(sources: [source]),
                                              model: "probe", convID: convID, started: started,
                                              slot: slot, announce: false)
            let messageID = placement?.messageID
            let applied = placement?.applySourceReview(review, to: view.store) ?? false
            writer.carry.add(AnswerPiece(text: "Zweiter Ketten-Schritt.", artifacts: AnswerArtifacts()))
            writer.flush(to: view.store, convID: convID, started: started)
            let after = view.store.current?.messages.last
            report.add("MECHANIK_KETTE", "nachricht=\(messageID?.uuidString.prefix(8) ?? "-") "
                       + "eingetragen=\(applied) gleiche_nachricht=\(after?.id == messageID) "
                       + "review_erhalten=\(after?.sourceReview == review) "
                       + "nachrichten=\(view.store.current?.messages.count ?? -1)")
            _ = view.store.removeConversation(convID)
        } else {
            report.add("MECHANIK_KETTE", "keine unterhaltung")
        }
    }

    private static func live(_ view: ChatView, _ report: SweepReport) async {
        guard view.settings.isConfigured else {
            report.add("LIVE_ABBRUCH", "kein schluessel konfiguriert")
            return
        }
        view.store.newConversation()
        guard let convID = view.store.currentID else {
            report.add("LIVE_ABBRUCH", "keine unterhaltung")
            return
        }

        let firstStarted = ContinuousClock.now
        view.input = "bitte aktuelle nachrichten aus berlin"
        await view.send()
        let firstVisibleAt = ContinuousClock.now
        let first = view.store.current?.messages.last(where: { $0.role == .assistant })
        let firstID = first?.id
        let firstText = first?.text ?? ""
        report.add("LIVE_ERSTE", "ms=\(msOf(firstStarted.duration(to: .now))) zeichen=\(firstText.count) "
                   + "quellen=\(first?.sources?.count ?? -1) "
                   + "review_beim_erscheinen=\(first?.sourceReview != nil) "
                   + "pruefung_laeuft=\(firstID.map { view.sourceChecks.contains($0) } ?? false) "
                   + "offene_pruefungen=\(view.sourceChecks.count)")

        var secondID: UUID?
        var secondText = ""
        let runningBeforeSecond = firstID.map { view.sourceChecks.contains($0) } ?? false
        var secondVisibleAt: ContinuousClock.Instant?
        if let firstID, runningBeforeSecond {
            let secondStarted = ContinuousClock.now
            view.input = "bitte aktuelle nachrichten aus hamburg"
            await view.send()
            secondVisibleAt = ContinuousClock.now
            let second = view.store.current?.messages.last(where: { $0.role == .assistant })
            secondID = second?.id
            secondText = second?.text ?? ""
            report.add("LIVE_ZWEITE", "ms=\(msOf(secondStarted.duration(to: .now))) "
                       + "neue_nachricht=\(secondID != nil && secondID != firstID) "
                       + "quellen=\(second?.sources?.count ?? -1) "
                       + "erste_lief_beim_senden=\(runningBeforeSecond) "
                       + "erste_lief_beim_commit=\(view.sourceChecks.contains(firstID)) "
                       + "zweite_laeuft=\(secondID.map { view.sourceChecks.contains($0) } ?? false) "
                       + "offen_beim_commit=\(view.sourceChecks.count)")
        } else {
            report.add("LIVE_ZWEITE", "uebersprungen weil nach der ersten Antwort keine Pruefung lief")
        }

        let deadline = ContinuousClock.now + .seconds(180)
        var waitedMs = 0
        var beats = 0
        var firstLandedMs: Int?
        var secondLandedMs: Int?
        while ContinuousClock.now < deadline {
            let open = view.sourceChecks
            let firstDone = reviewDone(view, firstID)
            let secondDone = reviewDone(view, secondID)
            if firstDone && firstLandedMs == nil {
                firstLandedMs = msOf(firstVisibleAt.duration(to: .now))
            }
            if let secondVisibleAt, secondDone && secondLandedMs == nil {
                secondLandedMs = msOf(secondVisibleAt.duration(to: .now))
            }
            if firstDone && secondDone {
                break
            }
            if open.isEmpty && !firstDone {
                break
            }
            if beats % 20 == 0 {
                flowMark("SOURCEBG warte offen=\(open.count) erste_fertig=\(firstDone) "
                         + "zweite_fertig=\(secondDone)")
            }
            beats += 1
            try? await Task.sleep(for: .milliseconds(500))
            waitedMs += 500
        }

        let messages = view.store.current?.messages ?? []
        let firstNow = messages.first { $0.id == firstID }
        let secondNow = messages.first { $0.id == secondID }
        report.add("LIVE_ENDE", "gewartet_ms=\(waitedMs) nachrichten=\(messages.count) "
                   + "erste_gleiche_nachricht=\(firstNow?.id == firstID) "
                   + "erste_text_unveraendert=\(firstNow?.text == firstText) "
                   + "erste_review_nach_ms=\(firstLandedMs ?? -1) "
                   + "erste_review=\(firstNow?.sourceReview?.verified ?? false)/"
                   + "\(firstNow?.sourceReview?.citedClaims ?? -1) "
                   + "zweite_gleiche_nachricht=\(secondNow?.id == secondID) "
                   + "zweite_text_unveraendert=\(secondNow?.text == secondText) "
                   + "zweite_review_nach_ms=\(secondLandedMs ?? -1) "
                   + "zweite_review=\(secondNow?.sourceReview?.verified ?? false)/"
                   + "\(secondNow?.sourceReview?.citedClaims ?? -1) "
                   + "offene_pruefungen=\(view.sourceChecks.count)")
        _ = view.store.removeConversation(convID)
    }

    private static func reviewDone(_ view: ChatView, _ id: UUID?) -> Bool {
        guard let id else { return true }
        return view.store.current?.messages.first { $0.id == id }?.sourceReview != nil
    }
}
#endif
