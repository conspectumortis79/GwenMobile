@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

extension DebugFeatureProbe {
    @MainActor static func answerAfterSend(_ view: ChatView, _ question: String) async
    -> (answer: ChatMessage?, ms: Int) {
        let started = ContinuousClock.now
        view.input = question
        await view.send()
        return (view.store.current?.messages.last(where: { $0.role == .assistant }),
                msOf(started.duration(to: .now)))
    }

    #if targetEnvironment(macCatalyst)
    static func macPresenceProbe() async {
        let report = SweepReport(file: "mac_presence.txt")
        let fenster = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        report.add("BEFEHLE", "beenden=cmd-q appTermination ersetzt, ausblenden=system cmd-h")
        report.add("FENSTERZUSTAND", "anzahl=\(fenster.count) ausgeblendet=\(fenster.filter { $0.isHidden }.count)")
        flowLog.info("MACPRÄSENZ bericht geschrieben")
    }
    #endif

    static func filePickerProbe(_ view: ChatView) async {
        let report = SweepReport(file: "file_picker.txt")
        report.add("TYPEN", FileKind.importTypes.map(\.identifier).joined(separator: ","))
        view.openFilePicker()
        await settled { Presenter.topViewController is UIDocumentPickerViewController }
        let picker = Presenter.topViewController as? UIDocumentPickerViewController
        report.add("PICKER", "praesentiert=\(picker != nil) wurzel_präsentiert=\(Presenter.windowRootViewController?.presentedViewController != nil) "
                   + "mehrfach=\(picker?.allowsMultipleSelection ?? false)")
        report.add("AKZEPTIERT", ["a.pdf", "b.rtf", "c.txt", "d.md", "e.csv", "f.json", "g.heic"]
            .map { "\($0)=\(FileKind(filename: $0)?.rawValue ?? "-")" }
            .joined(separator: " "))
        let vorher = view.pendingFiles.count
        view.importPicked([await madeTextFile()])
        await settled { view.pendingFiles.count > vorher && view.pendingFiles.last?.reading == false }
        let datei = view.pendingFiles.last
        report.add("ANHANG", "dateien=\(view.pendingFiles.count) name=\(datei?.name ?? "-") "
                   + "zeichen=\(datei?.chars ?? -1) art=\(datei?.kind.rawValue ?? "-") "
                   + "gelesen=\((datei?.chars ?? 0) > 0) fehler=\(datei?.failed ?? true)")
        let vorherDatei = datei.map { view.store.documents.storedURL(for: $0.file) != nil } ?? false
        if let datei { view.removePendingFile(datei) } else { view.pendingFiles = [] }
        let nachherDatei = datei.map { view.store.documents.storedURL(for: $0.file) != nil } ?? false
        report.add("ENTFERNEN", "vorher_da=\(vorherDatei) nachher_da=\(nachherDatei) pending=\(view.pendingFiles.count)")
        DocumentPresenter.shared.close()
        flowLog.info("DATEIPICKER fertig")
    }

    static func madeTextFile() async -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gwenpicker_\(UUID().uuidString.prefix(6)).txt")
        try? Data("Budget 85.000 Euro für den Ausbau des Lagers.".utf8).write(to: url)
        return url
    }

    static func keychainProbe() async {
        let report = SweepReport(file: "keychain_probe.txt")
        let store = KeychainKeyStore()
        let account = "probe_keychain"
        let marker = "gwenmobile-probe-\(UUID().uuidString.prefix(8))"
        report.add("LESEZUGRIFF", "vorher=\(zustand(store.read(account: account)))")
        let saved = store.save(marker, account: account)
        report.add("SCHLUESSELBUND", "speichern=\(saved) gelesen=\(store.read(account: account) == .value(marker))")
        store.save("", account: account)
        report.add("UEBERSCHREIBSCHUTZ", "wert_noch_da=\(store.read(account: account) == .value(marker))")
        store.delete(account: account)
        report.add("AURAEUMEN", "nach_loeschen_leer=\(store.read(account: account) == .absent)")
        flowLog.info("SCHLUESSELBUND fertig")
    }

    static func zustand(_ read: KeychainRead) -> String {
        switch read {
        case .value: return "da"
        case .absent: return "leer"
        case .blocked(let status): return "blockiert_\(status)"
        }
    }

    static func liveSpeech(_ view: ChatView) async {
        let report = SweepReport(file: "live_speech.txt")
        let speak = view.settings.voice.speakAnswers
        let conversation = view.settings.voice.conversationMode
        view.settings.voice.conversationMode = false
        view.settings.voice.speakAnswers = true
        view.store.newConversation()
        view.input = "Erkläre mir im Detail die Kernfusion, wie sie funktioniert."
        let started = Date()
        await view.send()
        let answer = view.store.current?.messages.last { $0.role == .assistant }?.text ?? ""
        let spoken = SpeechSynthesizer.stripForSpeech(answer)
        report.add("ANTWORT", "dauer_s=\(Int(Date().timeIntervalSince(started))) "
                   + "nachrichten=\(view.store.current?.messages.count ?? -1) "
                   + "spricht_noch=\(view.speech.isSpeaking)")
        report.add("MARKER", "antwort_marker=\(answer.contains("[")) "
                   + "gesprochen_marker=\(spoken.contains("[")) "
                   + "antwort_zeichen=\(answer.count) gesprochen_zeichen=\(spoken.count)")
        let sample = "Kernfusion setzt Energie frei [1, 3, 4]. Beides ist belegt [1;2]."
        let cleaned = SpeechSynthesizer.stripForSpeech(sample)
        report.add("KLAMMERN", "probe_klammern=\(sample.contains("[")) "
                   + "gesprochen_klammern=\(cleaned.contains("[")) "
                   + "text=\(TextLine.oneLine(cleaned, limit: 80))")
        view.speech.stop()
        view.settings.voice.speakAnswers = speak
        view.settings.voice.conversationMode = conversation
        flowLog.info("VORLESEN probe fertig")
    }

    static func inputReturnSends(_ view: ChatView) async {
        let report = SweepReport(file: "input_return.txt")
        report.add("SETUP", "konfiguriert=\(view.settings.isConfigured) bild=\(view.store.current?.messages.count ?? -1)")
        guard view.settings.isConfigured else {
            report.add("BLOCKIERT", "ohne schluessel oeffnet senden die einstellungen statt zu senden")
            return
        }
        view.store.newConversation()
        view.input = "Testfrage per Eingabetaste\n"
        await settled { (view.store.current?.messages.count ?? 0) > 1 }
        let gesendet = view.store.current?.messages.first(where: { $0.role == .user })
        report.add("EINGABETASTE", "gesendet=\(gesendet != nil) "
                   + "text=\(TextLine.oneLine(gesendet?.text ?? "-", limit: 40)) "
                   + "feld_lesen=\(view.input.isEmpty)")
        report.add("KEIN_DOPPELSENDEN", "benutzer=\(view.store.current?.messages.filter { $0.role == .user }.count ?? -1)")
        view.input = ""
        flowLog.info("EINGABETASTE fertig")
    }

    static func longInputSends(_ view: ChatView) async {
        let report = SweepReport(file: "long_input.txt")
        guard view.settings.isConfigured else {
            report.add("BLOCKIERT", "ohne schluessel oeffnet senden die einstellungen statt zu senden")
            flowLog.info("LANGEINGABE fertig")
            return
        }
        view.store.newConversation()
        let bullet = "Stichpunkt: Die Bibliothek öffnet um neun Uhr und schließt am Freitag früher; "
            + "der Markt findet am Samstag auf dem Platz statt; das Schwimmbad bleibt diese Woche geschlossen; "
            + "die Buslinie vier fährt bis Mitternacht; der Kurs beginnt am Montag im Raum zwei; "
        let instruction = ("Fasse die folgenden Stichpunkte in genau einem Satz zusammen. "
            + String(repeating: bullet, count: 8)).trimmed
        view.input = instruction + "\n"
        await settled { view.store.current?.messages.contains { $0.role == .user } ?? false }
        let sent = view.store.current?.messages.last(where: { $0.role == .user })
        let whole = sent?.text == instruction
        await settled({
            view.store.current?.messages.contains { $0.role == .assistant && !$0.text.isEmpty } ?? false
        }, rounds: 480)
        let answer = view.store.current?.messages.last(where: { $0.role == .assistant })
        report.add("LANGE_EINGABE", "ok=\(whole) zeichen=\(sent?.text.count ?? -1) unveraendert=\(whole) "
                   + "antwort=\(!(answer?.text.isEmpty ?? true)) antwort_zeichen=\(answer?.text.count ?? -1)")
        view.input = ""
        flowLog.info("LANGEINGABE fertig")
    }

    static func settled(_ check: @MainActor () -> Bool, rounds: Int = 60) async {
        for _ in 0..<rounds {
            if check() { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

}
#endif
