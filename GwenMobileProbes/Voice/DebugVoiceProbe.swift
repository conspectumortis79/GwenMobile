@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import AVFoundation
import UIKit

@MainActor
enum DebugVoiceProbe {
    struct Case {
        let name: String
        let sentence: String
        let listens: Bool
        let wanted: [String]
        let unwanted: [String]
        let sends: Bool
    }

    static func cases(_ settings: AppSettings) -> [Case] {
        let (wake, stop, cancel) = (settings.spokenWake, settings.spokenStop, settings.spokenCancel)
        return [
            Case(name: "stoppwort", sentence: "Wie spät ist es in Tokio? \(stop).", listens: false,
                 wanted: ["tokio"], unwanted: SignalPhrase(stop).words, sends: true),
            Case(name: "abbruchwort", sentence: "Das ist nur ein Test. \(cancel).", listens: false,
                 wanted: [], unwanted: [], sends: false),
            Case(name: "stille", sentence: "Wie wird das Wetter morgen in Ulm", listens: false,
                 wanted: ["wetter", "ulm"], unwanted: [], sends: true),
            Case(name: "weckwort", sentence: "Hallo zusammen, wie geht es euch? \(wake), wie hoch ist der Mount "
                 + "Everest? \(stop).", listens: true, wanted: ["everest"], unwanted: ["hallo"], sends: true),
        ]
    }
    static let trailingSilence = 6.0
    static let waitLimit = 40

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "voice_signal.txt")
        report.add("KONFIG", "sprache=\(L.lang.rawValue) weck=\(view.settings.spokenWake) "
                   + "stopp=\(view.settings.spokenStop) abbruch=\(view.settings.spokenCancel)")
        var passed = 0
        var total = 0
        for (label, fallback) in [("neu", false), ("alt", true)] {
            for entry in cases(view.settings) where !fallback || entry.name != "abbruchwort" {
                total += 1
                passed += await single(entry, fallback: fallback, label: label, view: view, report: report) ? 1 : 0
            }
        }
        total += 1
        passed += await microphone(report) ? 1 : 0
        total += 1
        passed += await siri(view, report: report) ? 1 : 0
        total += 1
        passed += await listeningMode(view, report: report) ? 1 : 0
        report.add("SUMME", "ok=\(passed)/\(total)")
        flowLog.info("VOICESIGNAL fertig ok=\(passed)/\(total)")
    }

    static func listVoices() async {
        let report = SweepReport(file: "voice_list.txt")
        report.add("MARKE", "voicelist-v2")
        report.add("BERECHTIGUNG", "status=\(AVSpeechSynthesizer.personalVoiceAuthorizationStatus.rawValue)")
        let voices = AVSpeechSynthesisVoice.speechVoices().sorted {
            if $0.language != $1.language { return $0.language < $1.language }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        for voice in voices {
            report.add("STIMME", "id=\(voice.identifier) name=\(voice.name) lang=\(voice.language) "
                       + "quality=\(voice.quality.rawValue) "
                       + "personal=\(voice.voiceTraits.contains(.isPersonalVoice))")
        }
        let personal = voices.filter { $0.voiceTraits.contains(.isPersonalVoice) }.count
        report.add("ENDE", "anzahl=\(voices.count) personal=\(personal)")
    }

    static func personalVoice(_ view: ChatView) async {
        let report = SweepReport(file: "personal_voice.txt")
        report.add("MARKE", "personalvoice-v1")
        let status = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        report.add("BERECHTIGUNG", "status=\(status.rawValue)")
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.voiceTraits.contains(.isPersonalVoice)
        }
        report.add("STIMMEN", "anzahl=\(voices.count) ids=\(voices.map(\.identifier).joined(separator: ","))")
        let options = VoiceCatalog.options(for: view.settings.language).filter(\.isPersonal)
        report.add("KATALOG", "anzahl=\(options.count) ids=\(options.map(\.id).joined(separator: ",")) "
                   + "sprache=\(view.settings.language.rawValue)")
        guard let voice = voices.first else {
            report.add("ERGEBNIS", "keine_personal_voice")
            return
        }
        let resolved = VoiceCatalog.voice(identifier: voice.identifier, language: view.settings.language)
        report.add("AUFLOESUNG", "id=\(resolved?.identifier ?? "-") "
                   + "personal=\(resolved?.voiceTraits.contains(.isPersonalVoice) ?? false)")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("personal_voice.caf")
        try? FileManager.default.removeItem(at: url)
        let sink = SpeechFileSink(url: url)
        let started = ContinuousClock.now
        let ok = await SpeechFileProbe.synthesise("Das ist meine eigene Stimme.", language: view.settings.language,
                                                  voice: voice, into: sink)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        report.add("WIEDERGABE", "ok=\(ok) frames=\(sink.frames) rate=\(Int(sink.sampleRate)) bytes=\(bytes) "
                   + "ms=\(msOf(started.duration(to: .now))) fehler=\(sink.failure ?? "-")")
        try? FileManager.default.removeItem(at: url)
    }

    private static func single(_ entry: Case, fallback: Bool, label: String, view: ChatView,
                               report: SweepReport) async -> Bool {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_\(entry.name).caf")
        try? FileManager.default.removeItem(at: url)
        let sink = SpeechFileSink(url: url)
        guard await SpeechFileProbe.synthesise(entry.sentence, language: view.settings.language, into: sink) else {
            report.add("\(label)_\(entry.name)", "ok=false stimme_fehlgeschlagen")
            return false
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let feed = FileAudioFeed(url: url, trailingSilence: trailingSilence)
        let voice = VoiceTranscriber(makeSource: {
            fallback ? BufferSpeechSource(feed: feed) as any LiveTranscribing
                : LiveTranscription.preferred(feed: { feed })
        })
        voice.signals = view.settings.voiceSignals
        let heard = HeardCommand()
        let started = Date()
        let onText: @MainActor (String) -> Void = { text in
            heard.text = text
            heard.at = Date()
        }
        if entry.listens { voice.listen(onText: onText) } else { voice.start(onText: onText) }
        var waited = 0
        var sawRecording = false
        while waited < waitLimit * 4, voice.state != .idle || waited < 4 {
            if voice.state == .recording { sawRecording = true }
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        let source = voice.sourceLabel
        voice.cancel()
        let text = heard.text ?? ""
        let folded = text.lowercased()
        let wantedOK = entry.wanted.allSatisfy { folded.contains($0) }
        let unwantedOK = !entry.unwanted.contains { folded.contains($0) }
        let sentOK = entry.sends ? !text.isEmpty : text.isEmpty
        var afterSpeech: Int?
        if let at = heard.at, let spoken = feed.spokenUntil { afterSpeech = Int(at.timeIntervalSince(spoken) * 1000) }
        let ok = sentOK && wantedOK && unwantedOK && voice.lastError == nil
        report.add("\(label)_\(entry.name)", "ok=\(ok) gesendet=\(!text.isEmpty) "
                   + "text=\(TextLine.oneLine(text, limit: 120)) "
                   + "ms_nach_sprechende=\(afterSpeech.map(String.init) ?? "-") "
                   + "ms_gesamt=\(Int(Date().timeIntervalSince(started) * 1000)) aufnahme_gesehen=\(sawRecording) "
                   + "quelle=\(source) fehler=\(voice.lastError?.message ?? "-")")
        return ok
    }

    static func longDictation(_ view: ChatView) async {
        let report = SweepReport(file: "voice_long.txt")
        let sentences = [
            "Die Sonne scheint über der alten Stadt und die Menschen gehen ruhig über den Marktplatz.",
            "Am Brunnen stehen Kinder und lachen, während die Vögel über die Dächer fliegen.",
            "Im kleinen Café an der Ecke duftet frischer Kaffee und die Kellnerin grüßt freundlich.",
            "Ein Fahrradfahrer klingelt und biegt vorsichtig in die schmale Gasse ein.",
            "Im Park blühen die ersten Blumen und auf der Wiese spielen zwei Hunde miteinander.",
            "Der Bäcker öffnet früh am Morgen und der Duft von Brot zieht durch die Straßen.",
            "Die Bibliothek am Rathaus hat bis zum Abend geöffnet und viele Leser sitzen am Fenster.",
            "Auf dem Fluss fahren kleine Boote und die Brücke spiegelt sich im ruhigen Wasser.",
        ]
        let texts = Array(repeating: sentences, count: 2).flatMap { $0 }
            + ["Zum Schluss steht ein Regenschirm neben der Tür."]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_long.caf")
        try? FileManager.default.removeItem(at: url)
        let sink = SpeechFileSink(url: url)
        guard await SpeechFileProbe.synthesise(texts, language: view.settings.language, into: sink,
                                               timeout: 180) else {
            report.add("LANGES_DIKTAT", "ok=false stimme_fehlgeschlagen fehler=\(sink.failure ?? "-")")
            flowLog.info("VOICELONG fertig")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let audioSeconds = sink.sampleRate > 0 ? Double(sink.frames) / sink.sampleRate : 0
        let feed = FileAudioFeed(url: url, trailingSilence: 6)
        let voice = VoiceTranscriber(makeSource: { LiveTranscription.preferred(feed: { feed }) })
        voice.signals = view.settings.voiceSignals
        let heard = HeardCommand()
        let started = Date()
        voice.start { text in heard.text = text }
        var waited = 0
        var pastOldLimit = false
        while waited < 960, voice.state != .idle || waited < 4 {
            if voice.state == .recording, Date().timeIntervalSince(started) >= 60 { pastOldLimit = true }
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        let text = heard.text ?? ""
        let folded = text.lowercased()
        let keepsStart = folded.contains("sonne")
        let keepsEnd = folded.contains("regenschirm")
        let ok = pastOldLimit && keepsStart && keepsEnd && voice.lastError == nil
        report.add("LANGES_DIKTAT", "ok=\(ok) audio_s=\(Int(audioSeconds)) aufnahme_ueber_60s=\(pastOldLimit) "
                   + "anfang=\(keepsStart) ende=\(keepsEnd) zeichen=\(text.count) "
                   + "ms=\(Int(Date().timeIntervalSince(started) * 1000)) fehler=\(voice.lastError?.message ?? "-")")
        voice.cancel()
        flowLog.info("VOICELONG fertig")
    }

    struct WordRound {
        let language: AppLanguage
        let sentence: String
        let phrases: [String]
    }

    static let rounds = [
        WordRound(language: .de, sentence: "Das Wetter morgen in Ulm. %@, wie spät ist es in Tokio? Jetzt senden.",
                  phrases: ["Hallo Computer", "Okay Computer", "Hey Computer", "Hallo Handy", "Hey Handy",
                            "Hallo Gwen"]),
        WordRound(language: .en, sentence: "The weather tomorrow in London. %@, what time is it in Tokyo? Send it now.",
                  phrases: ["Hey Computer", "Hello Computer", "Okay Computer", "Hey Gwen"]),
        WordRound(language: .en, sentence: "What time is it in Tokyo? %@.",
                  phrases: ["Send it now", "Send now", "Cancel that", "Cancel now"]),
    ]

    static func measureWords(_: ChatView) async {
        let report = SweepReport(file: "voice_words.txt")
        let home = L.lang
        let variants: [(String, @MainActor (FileAudioFeed) -> any LiveTranscribing)] = [
            ("analyzer_schnell", { feed in AnalyzerSpeechSource(feed: feed) }),
            ("sfspeech", { feed in BufferSpeechSource(feed: feed) }),
        ]
        for round in ProbeRounds.capped(rounds) {
            L.apply(round.language)
            for phrase in Array(round.phrases.prefix(1)) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_word.caf")
                try? FileManager.default.removeItem(at: url)
                let sink = SpeechFileSink(url: url)
                let sentence = round.sentence.replacingOccurrences(of: "%@", with: phrase)
                guard await SpeechFileProbe.synthesise(sentence, language: round.language, into: sink) else { continue }
                for (name, make) in variants {
                    let text = await hear(url: url, make: make)
                    let found = SignalPhrase(phrase).lastMatch(in: SignalPhrase.words(in: text)) != nil
                    report.add("\(round.language.rawValue)_\(name)_\(phrase.replacingOccurrences(of: " ", with: "_"))",
                               "erkannt=\(found) text=\(TextLine.oneLine(text, limit: 110))")
                }
                try? FileManager.default.removeItem(at: url)
            }
        }
        L.apply(home)
        flowLog.info("VOICEWORDS fertig")
    }

    private static func hear(url: URL, make: @MainActor (FileAudioFeed) -> any LiveTranscribing) async -> String {
        let feed = FileAudioFeed(url: url, trailingSilence: 4)
        let source = make(feed)
        let voice = VoiceTranscriber(makeSource: { source })
        voice.timing = VoiceTiming(silence: 4, nothingSaid: 25, maximum: 180)
        let heard = HeardCommand()
        voice.start { text in heard.text = text }
        var ticks = 0
        while ticks < 160, voice.state != .idle || ticks < 4 {
            try? await Task.sleep(for: .milliseconds(250))
            ticks += 1
        }
        voice.cancel()
        return heard.text ?? ""
    }

    static let quietLevels: [Float] = [0.5, 0.2, 0.08, 0.03]

    private struct QuietOutcome {
        let woke: Bool
        let everest: Bool
        let text: String
    }

    static func quietRecognition(_ view: ChatView) async {
        let report = SweepReport(file: "voice_quiet.txt")
        let home = L.lang
        let wake = view.settings.spokenWake
        let stop = view.settings.spokenStop
        let sentence = "Guten Tag zusammen. \(wake), wie hoch ist der Mount Everest? \(stop)."
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_quiet.caf")
        try? FileManager.default.removeItem(at: url)
        let sink = SpeechFileSink(url: url)
        guard await SpeechFileProbe.synthesise(sentence, language: view.settings.language, into: sink) else {
            report.add("STIMME", "ok=false weck=\(wake) stopp=\(stop)")
            flowLog.info("VOICEQUIET fertig")
            return
        }
        report.add("KONFIG", "sprache=\(L.lang.rawValue) weck=\(wake) stopp=\(stop) satz=\(sentence)")
        var lines: [String] = []
        for level in ProbeRounds.capped(quietLevels) {
            for (label, boost) in [("ohne", SpeechLevelBoost.off), ("mit", SpeechLevelBoost.standard)] {
                let outcome = await quietRound(url: url, level: level, boost: boost,
                                               signals: view.settings.voiceSignals)
                let name = "LEISE_\(Int(level * 100))_\(label)"
                lines.append(outcome.woke ? name : "!\(name)")
                report.add(name, "weckwort=\(outcome.woke) everest=\(outcome.everest) "
                           + "text=\(TextLine.oneLine(outcome.text, limit: 110))")
            }
        }
        report.add("SUMME", "weckwort_erkannt=\(lines.filter { !$0.hasPrefix("!") }.count)/\(lines.count) "
                   + lines.joined(separator: " "))
        try? FileManager.default.removeItem(at: url)
        L.apply(home)
        flowLog.info("VOICEQUIET fertig")
    }

    private static func quietRound(url: URL, level: Float, boost: SpeechLevelBoost,
                                   signals: VoiceSignals) async -> QuietOutcome {
        let feed = ScaledAudioFeed(url: url, trailingSilence: 5, level: level, boost: boost)
        let voice = VoiceTranscriber(makeSource: { LiveTranscription.preferred(feed: { feed }) })
        voice.signals = signals
        let heard = HeardCommand()
        voice.listen { text in heard.text = text }
        var ticks = 0
        var woke = false
        while ticks < waitLimit * 4 {
            if voice.state == .recording { woke = true }
            if voice.state == .idle, ticks >= 4 { break }
            if let spoken = feed.spokenUntil, Date().timeIntervalSince(spoken) >= 10 { break }
            try? await Task.sleep(for: .milliseconds(250))
            ticks += 1
        }
        voice.cancel()
        let text = heard.text ?? ""
        return QuietOutcome(woke: woke, everest: text.lowercased().contains("everest"), text: text)
    }

    static let offWake = "Hey Computer"

    static func listenOffWords(_: ChatView) async {
        let report = SweepReport(file: "voice_off.txt")
        let home = L.lang
        L.apply(.de)
        defer { L.apply(home) }
        let signals = VoiceWords.signals(wake: offWake, stop: "", cancel: "")
        let phrases = L.t(VoiceWords.listenOffKey).components(separatedBy: SignalPhrase.alternativeMarks)
            .map { $0.trimmed }.filter { !$0.isEmpty }
        guard let phrase = phrases.first else {
            report.add("SUMME", "ok=0/0 keine_phrase")
            flowLog.info("VOICEOFF fertig")
            return
        }
        let sentence = "\(offWake), \(phrase)."
        let heard = await heardInListening(sentence, language: .de, signals: signals)
        let command = heard.flatMap { VoiceCommand.command(in: $0, signals: signals) }
        let fits = command == .stopListening
        report.add("de_befehl", "passt=\(fits) befehl=\(command.map { "\($0)" } ?? "keiner") "
                   + "gehoert=\(heard ?? "-") satz=\(sentence)")
        report.add("SUMME", "ok=\(fits ? 1 : 0)/1")
        flowLog.info("VOICEOFF fertig")
    }

    static func listenOffFlow(_ view: ChatView) async {
        let report = SweepReport(file: "voice_off_flow.txt")
        let before = view.settings.voice.listenMode
        guard view.settings.isConfigured else {
            report.add("ZUHOERMODUS", "nicht_eingerichtet")
            return
        }
        view.settings.voice.listenMode = true
        var waited = 0
        while view.probeVoiceState != .waiting, waited < 40 {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        let on = (state: view.probeVoiceState, held: view.probeMicrophoneHeld)
        view.probeHandle(.stopListening)
        try? await Task.sleep(for: .milliseconds(1200))
        let off = (mode: view.settings.voice.listenMode, state: view.probeVoiceState, held: view.probeMicrophoneHeld)
        let ok = on.state == .waiting && on.held && !off.mode && off.state == .idle && !off.held
        report.add("ZUHOERMODUS_AUS", "ok=\(ok) vorher=\(on.state) mikro_vorher=\(on.held) "
                   + "modus_danach=\(off.mode) zustand_danach=\(off.state) mikro_danach=\(off.held)")
        view.settings.voice.listenMode = before
        report.add("ZURUECK", "modus=\(before)")
        flowLog.info("VOICEOFFFLOW fertig")
    }

    private static func heardInListening(_ sentence: String, language: AppLanguage,
                                         signals: VoiceSignals) async -> String? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_off.caf")
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        guard await SpeechFileProbe.synthesise(sentence, language: language, into: SpeechFileSink(url: url)) else {
            return nil
        }
        let feed = FileAudioFeed(url: url, trailingSilence: trailingSilence)
        let voice = VoiceTranscriber(makeSource: { LiveTranscription.preferred(feed: { feed }) })
        voice.signals = signals
        let heard = HeardCommand()
        voice.listen { text in heard.text = text }
        var ticks = 0
        while ticks < waitLimit * 4, voice.state != .idle || ticks < 4 {
            try? await Task.sleep(for: .milliseconds(250))
            ticks += 1
        }
        voice.cancel()
        return heard.text
    }

    static let settingsSteps = 14

    static func settingsShots(_ view: ChatView) async {
        let report = SweepReport(file: "siri_settings.txt")
        let bundle = Bundle.main
        report.add("NAME", "info_anzeige=\(bundle.infoDictionary?["CFBundleDisplayName"] as? String ?? "-") "
                   + "info_name=\(bundle.infoDictionary?["CFBundleName"] as? String ?? "-") "
                   + "lokal_anzeige=\(bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ?? "-") "
                   + "lokal_name=\(bundle.localizedInfoDictionary?["CFBundleName"] as? String ?? "-") "
                   + "objekt_anzeige=\(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "-") "
                   + "sprachen=\(bundle.preferredLocalizations.joined(separator: ","))")
        view.showSettings = true
        try? await Task.sleep(for: .milliseconds(1800))
        guard let window = Presenter.windowRootViewController?.view?.window,
              let sheet = Presenter.topViewController?.view,
              let scroll = ProviderProbe.formScrollView(in: sheet) else {
            report.add("EINSTELLUNGEN", "kein formular")
            view.showSettings = false
            return
        }
        var offset: CGFloat = 0
        for step in 0...settingsSteps {
            let reach = max(0, scroll.contentSize.height - scroll.bounds.height)
            offset = min(reach, offset)
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            try? await Task.sleep(for: .milliseconds(700))
            report.add("BILD_\(step)", "versatz=\(Int(offset)) inhalt=\(Int(scroll.contentSize.height)) "
                       + ViewerProbe.snapshot(window, named: "siri_settings_\(step).jpg", scale: window.screen.scale))
            guard offset < reach else { break }
            offset += scroll.bounds.height * 0.7
        }
        view.showSettings = false
        flowLog.info("SIRISETTINGS fertig")
    }

    private static func microphone(_ report: SweepReport) async -> Bool {
        let voice = VoiceTranscriber()
        voice.start { _ in }
        var waited = 0
        while voice.state != .recording, voice.lastError == nil, waited < 60 {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        let running = voice.probeRecorderActive
        let source = voice.sourceLabel
        let state = voice.state
        voice.cancel()
        try? await Task.sleep(for: .milliseconds(300))
        let ok = state == .recording && running && voice.state == .idle
        report.add("MIKROFON", "ok=\(ok) zustand=\(state) mikro_laeuft=\(running) quelle=\(source) "
                   + "nach_abbruch=\(voice.state) ms_bis_bereit=\(waited * 250) "
                   + "fehler=\(voice.lastError?.message ?? "-")")
        return ok
    }

    private static func listeningMode(_ view: ChatView, report: SweepReport) async -> Bool {
        let before = view.settings.voice.listenMode
        view.settings.voice.listenMode = true
        var waited = 0
        while view.probeVoiceState != .waiting, waited < 40 {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        let listening = view.probeVoiceState
        let awake = UIApplication.shared.isIdleTimerDisabled
        view.showSettings = true
        try? await Task.sleep(for: .milliseconds(800))
        let withSheet = view.probeVoiceState
        view.showSettings = false
        try? await Task.sleep(for: .milliseconds(1500))
        let afterSheet = view.probeVoiceState
        view.settings.voice.listenMode = false
        try? await Task.sleep(for: .milliseconds(800))
        let off = view.probeVoiceState
        view.settings.voice.listenMode = before
        let ok = listening == .waiting && awake && withSheet == .idle && afterSheet == .waiting && off == .idle
        report.add("ZUHOERMODUS", "ok=\(ok) an=\(listening) ms=\(waited * 250) bildschirm_wach=\(awake) "
                   + "mit_einstellungen=\(withSheet) danach=\(afterSheet) aus=\(off)")
        return ok
    }

    private static func siri(_ view: ChatView, report: SweepReport) async -> Bool {
        let before = view.probeVoiceState
        _ = try? await ListenIntent().perform()
        var waited = 0
        while view.probeVoiceState != .recording, waited < 60 {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        let state = view.probeVoiceState
        view.probeAbortVoice()
        try? await Task.sleep(for: .milliseconds(300))
        let ok = state == .recording
        report.add("SIRI_ABSICHT", "ok=\(ok) vorher=\(before) danach=\(state) ms=\(waited * 250) "
                   + "nach_abbruch=\(view.probeVoiceState)")
        return ok
    }
}
#endif
