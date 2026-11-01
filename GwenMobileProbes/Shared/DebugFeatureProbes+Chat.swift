@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

extension DebugFeatureProbe {
    static func chatError(_ view: ChatView) async {
        let report = SweepReport(file: "chat_error.txt")
        let store = view.store
        let settings = view.settings
        store.newConversation()
        guard let convID = store.current?.id else {
            report.add("CHATFEHLER", "keine unterhaltung")
            return
        }
        let turn = ModelTurn(messages: [ChatMessage(role: .user, text: "Nenne eine europaeische Hauptstadt.")],
                             images: [])
        let originalProvider = settings.provider
        let originalConnections = settings.connections
        settings.provider = .openAICompatible
        settings.connections.openAICompatible = OpenAICompatibleConfig(
            customURL: "https://gwenmobile-nicht-vorhanden.invalid/v1")
        await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date())
        settings.connections = originalConnections
        settings.provider = originalProvider
        let messages = store.current?.messages ?? []
        let last = messages.last
        report.add("CHATFEHLER", "nachrichten=\(messages.count) rolle=\(last?.role.rawValue ?? "-") "
                   + "warnung=\(last?.text.hasPrefix(AnswerError.marker) == true) "
                   + "text=\(TextLine.oneLine(last?.text ?? "", limit: 160))")
        flowLog.info("CHATERROR bericht geschrieben")
    }

    static func alertProbe(_ view: ChatView) async {
        let report = SweepReport(file: "alert_probe.txt")
        let handoff = L.FriendlyError(message: L.t("route_handoff_failed"), detail: "REWE",
                                      openSettings: false)
        let badKey = L.friendlyError("some failure", status: 401)
        view.probeRaise(handoff)
        view.probeRaise(badKey)
        view.probeRaise(handoff)
        let queue = view.probeAlerts
        report.add("WARTESCHLANGE", "anzahl=\(queue.count) erster=\(queue.first?.message ?? "-") "
                   + "oeffnet_settings=\(queue.first?.openSettings == true) "
                   + "zweiter=\(queue.last?.message ?? "-") zweiter_oeffnet=\(queue.last?.openSettings == true)")
        try? await Task.sleep(for: .milliseconds(900))
        if let window = Presenter.windowRootViewController?.view?.window {
            report.add("FENSTER", "bild=\(ViewerProbe.snapshot(window, named: "alert_probe.jpg")) "
                       + "sichtbar=\(view.probeAlerts.count)")
        } else {
            report.add("FENSTER", "kein fenster")
        }
        view.probeDismissAlert()
        report.add("NACH_ERSTEM_SCHLIESSEN", "anzahl=\(view.probeAlerts.count) "
                   + "erster=\(view.probeAlerts.first?.message ?? "-")")
        view.probeDismissAlert()
        report.add("NACH_ZWEITEM_SCHLIESSEN", "anzahl=\(view.probeAlerts.count)")
        flowLog.info("ALERTPROBE fertig")
    }

    static func languageFlow(_ view: ChatView) async {
        let report = SweepReport(file: "language_flow.txt")
        let vorher = view.settings.language
        view.settings.language = .en
        report.add("UMSCHALTUNG", "sprache=\(L.lang.rawValue) kopf=\(L.t("new_chat")) uhrzeit=\(Formatters.time(Date()))")
        view.store.newConversation()
        view.input = "Name three capitals in one short line."
        await view.send()
        let answer = view.store.current?.messages.last(where: { $0.role == .assistant })
        report.add("ANTWORT_EN", "zeichen=\(answer?.text.count ?? -1) titel=\(TextLine.oneLine(view.store.current?.title ?? "", limit: 160)) "
                   + "anfang=\(TextLine.oneLine(answer?.text ?? "", limit: 160))")
        view.settings.language = .es
        report.add("UMSCHALTUNG_ES", "sprache=\(L.lang.rawValue) kopf=\(L.t("new_chat")) einstellungen=\(L.t("settings")) uhrzeit=\(Formatters.time(Date()))")
        try? await Task.sleep(for: .milliseconds(900))
        if let window = Presenter.windowRootViewController?.view?.window {
            report.add("BILD_ES", ViewerProbe.snapshot(window, named: "language_es.jpg", scale: window.screen.scale))
        }
        view.store.newConversation()
        view.input = "Nombra tres capitales en una línea."
        await view.send()
        let respuesta = view.store.current?.messages.last(where: { $0.role == .assistant })
        report.add("ANTWORT_ES", "zeichen=\(respuesta?.text.count ?? -1) titel=\(TextLine.oneLine(view.store.current?.title ?? "", limit: 160)) "
                   + "anfang=\(TextLine.oneLine(respuesta?.text ?? "", limit: 160))")
        view.settings.language = .fr
        report.add("UMSCHALTUNG_FR", "sprache=\(L.lang.rawValue) kopf=\(L.t("new_chat")) einstellungen=\(L.t("settings")) uhrzeit=\(Formatters.time(Date()))")
        try? await Task.sleep(for: .milliseconds(900))
        if let window = Presenter.windowRootViewController?.view?.window {
            report.add("BILD_FR", ViewerProbe.snapshot(window, named: "language_fr.jpg", scale: window.screen.scale))
        }
        view.store.newConversation()
        view.input = "Nomme trois capitales en une ligne."
        await view.send()
        let reponse = view.store.current?.messages.last(where: { $0.role == .assistant })
        report.add("ANTWORT_FR", "zeichen=\(reponse?.text.count ?? -1) titel=\(TextLine.oneLine(view.store.current?.title ?? "", limit: 160)) "
                   + "anfang=\(TextLine.oneLine(reponse?.text ?? "", limit: 160))")
        view.settings.language = vorher
        report.add("ZURÜCK", "sprache=\(L.lang.rawValue) kopf=\(L.t("new_chat"))")
        flowLog.info("SPRACHE fertig")
    }

    static func thinkingFlow(_ view: ChatView) async {
        let report = SweepReport(file: "thinking_flow.txt")
        let vorher = view.settings.chatThinkingLevel
        view.settings.chatThinkingLevel = .off
        view.store.newConversation()
        view.input = "Nenne die Hauptstadt von Portugal in einem Satz."
        let started = ContinuousClock.now
        await view.send()
        let aus = view.store.current?.messages.last(where: { $0.role == .assistant })
        report.add("TIEFE_AUS", "stuft=\(aus?.thinking?.rawValue ?? "nil") ms=\(msOf(started.duration(to: .now))) "
                   + "zeichen=\(aus?.text.count ?? -1)")
        view.settings.chatThinkingLevel = .high
        view.input = "Und die Hauptstadt von Spanien, in einem Satz."
        let second = ContinuousClock.now
        await view.send()
        let an = view.store.current?.messages.last(where: { $0.role == .assistant })
        report.add("TIEFE_HOCH", "stuft=\(an?.thinking?.rawValue ?? "nil") ms=\(msOf(second.duration(to: .now))) "
                   + "zeichen=\(an?.text.count ?? -1)")
        view.settings.chatThinkingLevel = vorher
        report.add("ZURÜCK", "stuft=\(vorher.rawValue)")
        flowLog.info("DENKTIEFE fertig")
    }

    static func shortcutFlow(_ view: ChatView) async {
        let report = SweepReport(file: "shortcut_flow.txt")
        guard let url = URL(string: "gwenmobile://listen") else {
            report.add("KURZBEFEHL", "keine url")
            return
        }
        report.add("SCHEMA", "annahmefähig=\(UIApplication.shared.canOpenURL(url)) konfiguriert=\(view.settings.isConfigured)")
        await UIApplication.shared.open(url)
        let started = ContinuousClock.now
        let woke = await ProbeWait.until(10) { view.probeVoiceState != .idle }
        report.add("MIKRO_START", "zustand=\(view.probeVoiceState) geweckt=\(woke) "
                   + "ms=\(msOf(started.duration(to: .now)))")
        view.probeAbortVoice()
        _ = await ProbeWait.until(5) { view.probeVoiceState == .idle }
        report.add("MIKRO_ENDE", "zustand=\(view.probeVoiceState)")
        flowLog.info("KURZBEFEHL fertig")
    }

    static func translationRemembered(_ view: ChatView) async {
        let report = SweepReport(file: "translation_remembered.txt")
        let vorher = view.settings.voice.speakAnswers
        view.settings.voice.speakAnswers = false
        view.store.newConversation()
        view.pendingImages = [PendingPicture(image: textShot(), file: nil)]
        view.input = "Lies vor, was auf dem Bild steht"
        await view.send()
        let abgelesen = view.store.current?.messages.last(where: { $0.role == .assistant })
        view.input = "Übersetze den Text auf dem Foto ins Englische"
        await view.send()
        let übersetzt = view.store.current?.messages.last(where: { $0.role == .assistant })
        let text = übersetzt?.text ?? ""
        report.add("ERINNERTES_BILD", "anhang=nein runde=2"
                   + " vorlage=\(TextLine.oneLine(abgelesen?.text ?? "", limit: 70))"
                   + " signatur_vorlage=\(abgelesen?.model ?? "-")")
        report.add("ERINNERTES_BILD_ANTWORT", "modell=\(übersetzt?.model ?? "-") zeichen=\(text.count) "
                   + "antwort=\(TextLine.oneLine(text, limit: 150))")
        let lower = text.lowercased()
        report.add("ERINNERTES_BILD_TREFFER", "englisch=\(lower.contains("coffee") || lower.contains("table")) "
                   + "betrag=\(text.contains("14")) keine_rückgabe_der_vorlage=\(!text.isEmpty && text != abgelesen?.text)")
        view.pendingImages = []
        view.settings.voice.speakAnswers = vorher
        flowLog.info("ÜBERSETZUNG erinnertes bild fertig")
    }

    static func photoText(_ view: ChatView) async {
        let report = SweepReport(file: "photo_text.txt")
        view.store.newConversation()
        view.pendingImages = [PendingPicture(image: textShot(), file: nil)]
        view.input = "Übersetze den Text, den du auf dem Foto siehst, wörtlich ins Englische"
        let t0 = ContinuousClock.now
        await view.send()
        let answer = view.store.current?.messages.last(where: { $0.role == .assistant })
        let text = answer?.text ?? ""
        report.add("PHOTOTEXT", "ms=\(msOf(t0.duration(to: .now))) modell=\(answer?.model ?? "-") "
                   + "vision=\(view.settings.visionModel) bilder=\(answer?.outImages?.count ?? -1) "
                   + "zeichen=\(text.count) antwort=\(TextLine.oneLine(text, limit: 160))")
        report.add("PHOTOTEXT_TREFFER", "coffee=\(text.lowercased().contains("coffee")) "
                   + "cake=\(text.lowercased().contains("cake")) "
                   + "betrag=\(text.contains("14")) english=\(text.lowercased().contains("table"))")
        flowLog.info("PHOTOTEXT fertig")
    }

    static func textShot() -> UIImage {
        ReceiptCard.receiptCard(fontSize: 44, lineSpacing: 14)
    }

}
#endif
