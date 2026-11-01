@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import Combine
import XCTest
import GwenMobileKit

final class SignalPhraseTests: GwenTestCase {
    func testWordsAreFoldedAndCarryTheirPlaceInTheText() {
        let text = "Hey Gwen, wie spät?"
        let words = SignalPhrase.words(in: text)
        XCTAssertEqual(words.map(\.folded), ["hey", "gwen", "wie", "spat"])
        XCTAssertEqual(String(text[words[1].range]), "Gwen")
    }

    func testOneMisheardLetterIsToleratedOnlyInLongerWords() {
        XCTAssertTrue(SignalPhrase.similar("gwen", "gwenn"))
        XCTAssertTrue(SignalPhrase.similar("senden", "sende"))
        XCTAssertFalse(SignalPhrase.similar("gwen", "when"), "zwei Abweichungen sind ein anderes Wort")
        XCTAssertFalse(SignalPhrase.similar("hey", "hay"), "kurze Wörter müssen genau stimmen")
    }
}

final class VoiceCommandTests: GwenTestCase {
    private let signals = VoiceSignals(wake: "Hey Gwen", stop: "Gwen senden", cancel: "Gwen abbrechen")

    private func request(_ transcript: String) -> String? {
        VoiceCommand.heardWake(in: transcript, wake: signals.wake)?.request
    }

    func testTheStopWordAtTheEndSendsEverythingBeforeIt() {
        XCTAssertEqual(VoiceCommand.verdict(for: "Wie spät ist es in Tokio? Gwen senden.", signals: signals),
                       .send("Wie spät ist es in Tokio?"), "das Fragezeichen bleibt, das Stoppwort geht")
        XCTAssertEqual(VoiceCommand.verdict(for: "wie wird das Wetter, Gwenn senden", signals: signals),
                       .send("wie wird das Wetter"), "ein falsch gehörter Buchstabe stoppt trotzdem")
    }

    func testTheStopWordInTheMiddleKeepsListening() {
        XCTAssertEqual(VoiceCommand.verdict(for: "Gwen senden bitte das Foto", signals: signals), .listening)
        XCTAssertEqual(VoiceCommand.verdict(for: "Wie spät ist es", signals: signals), .listening)
    }

    func testTheCancelWordAtTheEndDiscards() {
        XCTAssertEqual(VoiceCommand.verdict(for: "Das ist nur ein Test. Gwen abbrechen.", signals: signals), .discard)
    }

    func testNoSignalWordsMeansOnlyTheTimingDecides() {
        XCTAssertEqual(VoiceCommand.verdict(for: "irgendwas senden", signals: .none), .listening)
    }

    func testOnlyTheWholeRequestCountsAsTheNewChatCommand() {
        let signals = VoiceSignals(wake: "Hey Gwen", stop: "Gwen senden", cancel: "Gwen abbrechen",
                                   newChat: "Neuer Chat, Neue Session")
        XCTAssertEqual(VoiceCommand.command(in: "Neuer Chat", signals: signals), .newChat)
        XCTAssertEqual(VoiceCommand.command(in: "neue Session.", signals: signals), .newChat)
        XCTAssertEqual(VoiceCommand.command(in: "Neue Sesion", signals: signals), .newChat,
                       "ein falsch gehörter Buchstabe zählt noch")
        XCTAssertNil(VoiceCommand.command(in: "Erklär mir, wie man in Excel eine neue Session startet",
                                          signals: signals))
        XCTAssertNil(VoiceCommand.command(in: "Neuer", signals: signals))
        XCTAssertNil(VoiceCommand.command(in: "Neuer Chat", signals: self.signals), "ohne Befehlswort kein Befehl")
    }

    func testOnlyWhatFollowsTheLastWakeWordIsTheRequest() {
        XCTAssertEqual(request("Hallo zusammen. Hey Gwen, wie hoch ist der Everest"), "wie hoch ist der Everest")
        XCTAssertEqual(request("hey gwen. Hey Gwen! Wetter"), "Wetter")
        XCTAssertEqual(request("Hey Gwen"), "")
        XCTAssertNil(request("Hallo zusammen"))
        XCTAssertEqual(VoiceCommand.heardWake(in: "Hallo Hey Gwen Wetter", wake: signals.wake)?.anchor, 3)
    }

    func testTheRequestIsFoundByItsPlaceWhenTheWakeWordWasRewritten() {
        XCTAssertEqual(VoiceCommand.request(in: "Hallo Hey G, wie spät ist es", from: 3), "wie spät ist es")
        XCTAssertEqual(VoiceCommand.request(in: "Hallo Hey G", from: 3), "")
        XCTAssertNil(VoiceCommand.request(in: "Hallo Hey", from: 3), "zu wenig Wörter: nichts erfinden")
        XCTAssertNil(VoiceCommand.request(in: "Hallo Hey G", from: 0), "ohne Weckwort gibt es keine Stelle")
    }
}

final class WakeAnchorTests: GwenTestCase {
    private let wake = SignalPhrase("Hey Gwen")

    func testWithoutAHeardWakeWordNothingStarts() {
        var anchor = WakeAnchor()
        XCTAssertNil(anchor.request(in: "Kann wie viel Uhr haben wir", wake: wake))
        XCTAssertEqual(anchor.position, 0)
        XCTAssertFalse(anchor.revised)
    }

    func testARewrittenWakeWordKeepsTheRequestGoing() {
        var anchor = WakeAnchor()
        XCTAssertEqual(anchor.request(in: "Hallo Hey Gwen", wake: wake), "")
        XCTAssertEqual(anchor.position, 3)
        XCTAssertEqual(anchor.request(in: "Hallo Hey G wie viel Uhr haben wir", wake: wake), "wie viel Uhr haben wir")
        XCTAssertTrue(anchor.revised)
    }

    func testTheWakeWordSaidAgainStartsTheRequestAnew() {
        var anchor = WakeAnchor()
        _ = anchor.request(in: "Hey Gwen Wetter", wake: wake)
        XCTAssertEqual(anchor.request(in: "Hey Gwen Wetter nein Hey Gwen Uhrzeit", wake: wake), "Uhrzeit")
        XCTAssertEqual(anchor.position, 6)
        XCTAssertFalse(anchor.revised)
    }
}

final class VoiceTimingTests: GwenTestCase {
    private let timing = VoiceTiming.standard
    private let start = Date(timeIntervalSince1970: 1_000)

    func testTheStandardAllowsThreeMinutesAndFourSecondsOfSilence() {
        XCTAssertEqual(timing, VoiceTiming(silence: 4, nothingSaid: 8, maximum: 180))
    }

    func testSilenceAfterSpeechSends() {
        let last = start.addingTimeInterval(3)
        XCTAssertEqual(timing.verdict(startedAt: start, lastChange: last, hasText: true,
                                      now: last.addingTimeInterval(3.9)), .keep)
        XCTAssertEqual(timing.verdict(startedAt: start, lastChange: last, hasText: true,
                                      now: last.addingTimeInterval(4)), .finish)
    }

    func testNothingSaidEndsAfterItsOwnLimit() {
        XCTAssertEqual(timing.verdict(startedAt: start, lastChange: nil, hasText: false,
                                      now: start.addingTimeInterval(7.9)), .keep)
        XCTAssertEqual(timing.verdict(startedAt: start, lastChange: nil, hasText: false,
                                      now: start.addingTimeInterval(8)), .nothingSaid)
    }

    func testTheUpperLimitEndsEvenWhileTalking() {
        let now = start.addingTimeInterval(180)
        XCTAssertEqual(timing.verdict(startedAt: start, lastChange: now, hasText: true, now: now), .finish)
        XCTAssertEqual(timing.remaining(startedAt: start, now: start.addingTimeInterval(170.2)), 10)
        XCTAssertEqual(timing.remaining(startedAt: start, now: start.addingTimeInterval(185)), 0)
    }
}

final class TranscriptAssemblyTests: GwenTestCase {
    func testSettledPiecesStayAndThePendingOneIsReplaced() {
        var assembly = TranscriptAssembly()
        assembly.revise("Wie spä")
        assembly.revise("Wie spät ist")
        XCTAssertEqual(assembly.text, "Wie spät ist")
        assembly.settle("Wie spät ist es?")
        assembly.revise("Gwen")
        XCTAssertEqual(assembly.text, "Wie spät ist es? Gwen")
        assembly.settlePending()
        XCTAssertEqual(assembly.pending, "")
        XCTAssertEqual(assembly.text, "Wie spät ist es? Gwen")
    }

    func testManySettledPiecesJoinInOrder() {
        var assembly = TranscriptAssembly()
        assembly.settle("erstens")
        assembly.settle("zweitens")
        assembly.settle("drittens")
        XCTAssertEqual(assembly.text, "erstens zweitens drittens")
    }

    func testALongListeningPhaseKeepsEverything() {
        var assembly = TranscriptAssembly()
        let long = String(repeating: "a", count: 12_000)
        assembly.settle(long + " Hey Gwen")
        XCTAssertEqual(assembly.text, long + " Hey Gwen")
        XCTAssertTrue(assembly.text.hasSuffix("Hey Gwen"))
    }
}

final class ListenGateTests: GwenTestCase {
    private func gate(enabled: Bool = true, configured: Bool = true, foreground: Bool = true,
                      microphoneLive: Bool = false, working: Bool = false,
                      speaking: Bool = false, sheetOpen: Bool = false,
                      conversation: Bool = false, bargeIn: Bool = true) -> ListenGate {
        ListenGate(enabled: enabled, configured: configured, foreground: foreground,
                   microphoneLive: microphoneLive, working: working, speaking: speaking, sheetOpen: sheetOpen,
                   conversation: conversation, bargeIn: bargeIn)
    }

    func testTheModeListensOnlyWhileTheAppIsFreeToHear() {
        XCTAssertTrue(gate().mayListen)
        XCTAssertFalse(gate(enabled: false).mayListen)
        XCTAssertFalse(gate(configured: false).mayListen)
        XCTAssertFalse(gate(working: true).mayListen, "während eine Antwort läuft, wird kein neuer Auftrag gehört")
        XCTAssertFalse(gate(speaking: true).mayListen, "die eigene Vorlesestimme darf nichts auslösen")
        XCTAssertFalse(gate(sheetOpen: true).mayListen)
    }

    func testTheCancelWordIsHeardWhileTheAnswerRunsOrSpeaks() {
        XCTAssertTrue(gate(working: true).mayCancel)
        XCTAssertTrue(gate(speaking: true).mayCancel)
        XCTAssertTrue(gate(working: true, speaking: true).mayCancel)
        XCTAssertFalse(gate().mayCancel)
        XCTAssertFalse(gate(working: true, sheetOpen: true).mayCancel)
        XCTAssertFalse(gate(foreground: false, working: true).mayCancel)
        XCTAssertTrue(gate(foreground: false, microphoneLive: true, working: true).mayCancel)
        XCTAssertFalse(gate(working: true, conversation: true).mayCancel)
        XCTAssertFalse(gate(enabled: false, working: true).mayCancel)
        XCTAssertFalse(gate(configured: false, working: true).mayCancel)
    }

    func testInTheBackgroundOnlyAnAlreadyRunningMicrophoneKeepsListening() {
        XCTAssertFalse(gate(foreground: false).mayListen, "aus dem Hintergrund startet iOS kein Mikrofon")
        XCTAssertTrue(gate(foreground: false, microphoneLive: true).mayListen)
        XCTAssertFalse(gate(foreground: false, microphoneLive: true, speaking: true).mayListen)
        XCTAssertFalse(gate(enabled: false, foreground: false, microphoneLive: true).mayListen)
    }

    func testTheGateDefaultsToNoConversation() {
        let plain = ListenGate(enabled: true, configured: true, foreground: true,
                               microphoneLive: false, working: false, speaking: false, sheetOpen: false)
        XCTAssertFalse(plain.conversation)
        XCTAssertTrue(plain.mayListen)
    }

    func testConversationModeKeepsListeningWhileTheAnswerRunsAndSpeaks() {
        XCTAssertTrue(gate(working: true, conversation: true).mayListen)
        XCTAssertTrue(gate(speaking: true, conversation: true).mayListen)
        XCTAssertTrue(gate(working: true, speaking: true, conversation: true).mayListen)
        XCTAssertFalse(gate(working: true, sheetOpen: true, conversation: true).mayListen)
        XCTAssertFalse(gate(foreground: false, working: true, conversation: true).mayListen)
        XCTAssertTrue(gate(foreground: false, microphoneLive: true, working: true, conversation: true).mayListen)
    }

    func testConversationWithoutBargeInWaitsForTheAnswerToEnd() {
        XCTAssertFalse(gate(speaking: true, conversation: true, bargeIn: false).mayListen)
        XCTAssertTrue(gate(working: true, conversation: true, bargeIn: false).mayListen)
        XCTAssertTrue(gate(conversation: true, bargeIn: false).mayListen)
    }

    func testTheMicrophoneIsHeldWhileTheModeIsOnWhateverElseHappens() {
        XCTAssertTrue(gate(working: true, speaking: true, sheetOpen: true).holdsMicrophone,
                      "zwischen zwei Anfragen bleibt das Mikrofon an")
        XCTAssertTrue(gate(foreground: false).holdsMicrophone)
        XCTAssertFalse(gate(enabled: false).holdsMicrophone)
        XCTAssertFalse(gate(configured: false).holdsMicrophone)
    }

    func testTheConversationTimingUsesTheOrdinarySilenceAndStaysOpen() {
        XCTAssertEqual(VoiceTiming.conversation(silence: 2),
                       VoiceTiming(silence: 2, nothingSaid: 86_400, maximum: 86_400))
    }

    func testTheScreenStaysAwakeWhileTheModeIsOnInTheForeground() {
        XCTAssertTrue(gate(working: true).keepsScreenAwake)
        XCTAssertFalse(gate(enabled: false).keepsScreenAwake)
        XCTAssertFalse(gate(foreground: false).keepsScreenAwake)
    }
}

final class VoiceWordsTests: GwenTestCase {
    func testEmptyWordsFallBackToTheDefaultsOfTheAppLanguage() {
        L.apply(.de)
        let german = VoiceWords.signals(wake: " ", stop: "", cancel: "Hör auf")
        XCTAssertEqual(german.wake, SignalPhrase("Hey Computer"))
        XCTAssertEqual(german.stop, SignalPhrase("Jetzt senden"))
        XCTAssertEqual(german.cancel, SignalPhrase("Hör auf"))
        XCTAssertEqual(german.hints, ["Hey Computer", "Jetzt senden", "Hör auf",
                                      "Neuer Chat", "Neue Session", "New Chat", "New Session",
                                      "Zuhören beenden", "Zuhörmodus aus", "Stop listening"],
                       "the recognizer gets the words as they are written - with umlaut")
        L.apply(.en)
        let english = VoiceWords.signals(wake: " ", stop: "", cancel: "Hör auf")
        XCTAssertEqual(english.wake, SignalPhrase("Hey Computer"))
        XCTAssertEqual(english.stop, SignalPhrase("Send it now"))
        XCTAssertEqual(english.cancel, SignalPhrase("Hör auf"))
        XCTAssertEqual(english.hints, ["Hey Computer", "Send it now", "Hör auf",
                                       "New chat", "New session", "Neuer Chat", "Neue Session",
                                       "Stop listening", "Listening off"])
    }

    func testTheNewChatWordUnderstandsGermanAndEnglishByDefault() {
        let signals = VoiceWords.signals(wake: "", stop: "", cancel: "", newChat: " ")
        XCTAssertEqual(VoiceCommand.command(in: "Neue Session", signals: signals), .newChat)
        XCTAssertEqual(VoiceCommand.command(in: "new chat", signals: signals), .newChat)
    }

    func testTheListeningOffWordUnderstandsBothLanguagesByDefault() {
        L.apply(.de)
        let signals = VoiceWords.signals(wake: "", stop: "", cancel: "", listenOff: " ")
        XCTAssertEqual(VoiceCommand.command(in: "Zuhören beenden.", signals: signals), .stopListening)
        XCTAssertEqual(VoiceCommand.command(in: "Zuhörmodus aus", signals: signals), .stopListening)
        XCTAssertEqual(VoiceCommand.command(in: "stopp Listening", signals: signals), .stopListening,
                       "this is how the German recognizer writes the English word on the iPhone")
        L.apply(.en)
        let english = VoiceWords.signals(wake: "", stop: "", cancel: "")
        XCTAssertEqual(VoiceCommand.command(in: "listening off.", signals: english), .stopListening)
        XCTAssertNil(VoiceCommand.command(in: "Zahar and Beenden", signals: english))
    }

    func testOnlyTheWholeRequestSwitchesListeningOff() {
        let signals = VoiceWords.signals(wake: "", stop: "", cancel: "")
        XCTAssertNil(VoiceCommand.command(in: "Erklär mir, wie man das Zuhören am Telefon beendet", signals: signals))
        XCTAssertNil(VoiceCommand.command(in: "Zuhören", signals: signals))
        XCTAssertEqual(VoiceCommand.command(in: "Neuer Chat", signals: signals), .newChat,
                       "neuer Chat und Zuhörmodus aus bleiben zwei Befehle")
        XCTAssertNil(VoiceCommand.command(in: "Zuhören beenden",
                                          signals: VoiceSignals(wake: "Hey Gwen", stop: "Gwen senden", cancel: "")),
                     "ohne Befehlswort kein Befehl")
    }

    func testAnOwnListeningOffWordReplacesTheDefaults() {
        let signals = VoiceWords.signals(wake: "", stop: "", cancel: "", listenOff: "Feierabend; Ruhe bitte")
        XCTAssertEqual(VoiceCommand.command(in: "Feierabend", signals: signals), .stopListening)
        XCTAssertEqual(VoiceCommand.command(in: "Ruhe bitte!", signals: signals), .stopListening)
        XCTAssertNil(VoiceCommand.command(in: "Zuhören beenden", signals: signals))
        XCTAssertTrue(signals.hints.contains("Ruhe bitte"), "die Erkennung bekommt das eigene Wort als Hinweis")
    }

    func testAnOwnNewChatWordReplacesTheDefaults() {
        let signals = VoiceWords.signals(wake: "", stop: "", cancel: "", newChat: "Frisch anfangen; Leeren")
        XCTAssertEqual(VoiceCommand.command(in: "frisch anfangen", signals: signals), .newChat)
        XCTAssertEqual(VoiceCommand.command(in: "Leeren", signals: signals), .newChat)
        XCTAssertNil(VoiceCommand.command(in: "Neuer Chat", signals: signals))
    }
}

@MainActor
final class SentWords {
    var items: [String] = []
}

@MainActor
final class FakeLiveSource: LiveTranscribing {
    let label = "fake"
    private(set) var isCapturing = false
    private(set) var starts = 0
    private var onText: (@MainActor (String) -> Void)?

    func start(locale: Locale, hints: [String], onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        isCapturing = true
        starts += 1
        self.onText = onText
    }

    func stop() { isCapturing = false }

    func say(_ text: String) { onText?(text) }
}

@MainActor
final class CountingCue: SoundCueing {
    private(set) var played = 0

    func play() { played += 1 }
}

@MainActor
final class VoiceTranscriberTests: GwenTestCase {
    private func transcriber(_ source: FakeLiveSource, timing: VoiceTiming = .standard,
                             cue: CountingCue = CountingCue(), sent: CountingCue = CountingCue()) -> VoiceTranscriber {
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true }, sentCue: sent)
        voice.onWakeWord = { cue.play(); return nil }
        voice.signals = VoiceSignals(wake: "Hey Gwen", stop: "Gwen senden", cancel: "Gwen abbrechen")
        voice.timing = timing
        return voice
    }

    private func waitFor(_ voice: VoiceTranscriber, _ state: VoiceTranscriber.State) async {
        for _ in 0..<200 where voice.state != state { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func testTheStopWordSendsTheRequestAtOnce() async {
        let source = FakeLiveSource()
        let voice = transcriber(source)
        let sent = SentWords()
        voice.start { sent.items.append($0) }
        await waitFor(voice, .recording)
        source.say("Wie spät ist es")
        XCTAssertEqual(voice.liveText, "Wie spät ist es")
        source.say("Wie spät ist es Gwen senden")
        XCTAssertEqual(sent.items, ["Wie spät ist es"])
        XCTAssertEqual(voice.state, .idle)
        XCTAssertFalse(source.isCapturing, "nach dem Absenden ist das Mikrofon aus")
    }

    func testTheCancelWordDiscardsWithoutAnError() async {
        let source = FakeLiveSource()
        let voice = transcriber(source)
        let sent = SentWords()
        voice.start { sent.items.append($0) }
        await waitFor(voice, .recording)
        source.say("Das war nichts Gwen abbrechen")
        XCTAssertTrue(sent.items.isEmpty)
        XCTAssertNil(voice.lastError)
        XCTAssertEqual(voice.state, .idle)
    }

    func testSilenceSendsWhatWasSaid() async {
        let source = FakeLiveSource()
        let voice = transcriber(source, timing: VoiceTiming(silence: 0.3, nothingSaid: 8, maximum: 180))
        let sent = SentWords()
        voice.start { sent.items.append($0) }
        await waitFor(voice, .recording)
        source.say("Wie wird das Wetter")
        await waitFor(voice, .idle)
        XCTAssertEqual(sent.items, ["Wie wird das Wetter"])
    }

    func testTheWakeWordStartsTheRequestAndOnlyWhatFollowsIsSent() async {
        let source = FakeLiveSource()
        let voice = transcriber(source)
        let sent = SentWords()
        voice.listen { sent.items.append($0) }
        await waitFor(voice, .waiting)
        source.say("Hallo zusammen")
        XCTAssertEqual(voice.state, .waiting, "ohne Weckwort passiert nichts")
        source.say("Hallo zusammen Hey Gwen wie hoch ist der Everest")
        XCTAssertEqual(voice.state, .recording)
        XCTAssertEqual(voice.liveText, "wie hoch ist der Everest")
        source.say("Hallo zusammen Hey Gwen wie hoch ist der Everest Gwen senden")
        XCTAssertEqual(sent.items, ["wie hoch ist der Everest"])
    }

    func testARequestSurvivesTheRecognizerRewritingTheWakeWord() async {
        let source = FakeLiveSource()
        let voice = transcriber(source)
        let sent = SentWords()
        voice.listen { sent.items.append($0) }
        await waitFor(voice, .waiting)
        source.say("Hallo Hey Gwen")
        XCTAssertEqual(voice.state, .recording)
        source.say("Hallo Hey G wie spät ist es")
        XCTAssertEqual(voice.liveText, "wie spät ist es", "die Erkennung hat „Gwen“ nachträglich zu „G“ gemacht")
        source.say("Hallo Hey G wie spät ist es Gwen senden")
        XCTAssertEqual(sent.items, ["wie spät ist es"])
    }

    func testTheWakeWordIsAnsweredWithOneSpokenGreeting() async {
        let source = FakeLiveSource()
        let cue = CountingCue()
        let voice = transcriber(source, cue: cue)
        voice.listen { _ in }
        await waitFor(voice, .waiting)
        source.say("Hallo zusammen")
        XCTAssertEqual(cue.played, 0, "ohne Weckwort bleibt es still")
        source.say("Hallo zusammen Hey Gwen")
        source.say("Hallo zusammen Hey Gwen wie spät")
        source.say("Hallo zusammen Hey Gwen wie spät Hey Gwen es ist")
        XCTAssertEqual(cue.played, 1, "die Begrüßung kommt einmal, wenn das Zuhören beginnt")
    }

    func testWaitingForTheWakeWordDoesNotRedrawTheScreenEveryTick() async {
        let source = FakeLiveSource()
        let voice = transcriber(source)
        voice.listen { _ in }
        await waitFor(voice, .waiting)
        let changes = LockedValue(0)
        let watch = voice.objectWillChange.sink { _ in changes.mutate { $0 += 1 } }
        try? await Task.sleep(for: VoiceTranscriber.tick * 4)
        watch.cancel()
        XCTAssertEqual(changes.current, 0, "stundenlanges Zuhören darf die Oberfläche nicht ständig neu zeichnen")
    }

    func testARequestSentByTheStopWordIsAnsweredWithTheSentTone() async {
        let source = FakeLiveSource()
        let cue = CountingCue()
        let sent = CountingCue()
        let voice = transcriber(source, cue: cue, sent: sent)
        let requests = SentWords()
        voice.listen { requests.items.append($0) }
        await waitFor(voice, .waiting)
        source.say("Hey Gwen wie spät ist es")
        XCTAssertEqual(sent.played, 0, "solange gesprochen wird, kommt kein zweiter Ton")
        source.say("Hey Gwen wie spät ist es Gwen senden")
        XCTAssertEqual(requests.items, ["wie spät ist es"])
        XCTAssertEqual(cue.played, 1, "die Begrüßung kommt einmal")
        XCTAssertEqual(sent.played, 1, "die Anfrage ist angekommen")
    }

    func testSilenceAfterTheRequestAlsoPlaysTheSecondTone() async {
        let source = FakeLiveSource()
        let sent = CountingCue()
        let voice = transcriber(source, timing: VoiceTiming(silence: 0.3, nothingSaid: 8, maximum: 180), sent: sent)
        voice.listen { _ in }
        await waitFor(voice, .waiting)
        source.say("Hey Gwen wie wird das Wetter")
        await waitFor(voice, .idle)
        XCTAssertEqual(sent.played, 1)
    }

    func testNoSecondToneWhenNothingIsSent() async {
        let source = FakeLiveSource()
        let sent = CountingCue()
        let voice = transcriber(source, timing: VoiceTiming(silence: 4, nothingSaid: 0.2, maximum: 180), sent: sent)
        voice.listen { _ in XCTFail("nichts wird gesendet") }
        await waitFor(voice, .waiting)
        source.say("Hey Gwen das war nichts Gwen abbrechen")
        XCTAssertEqual(voice.state, .idle)
        voice.listen { _ in XCTFail("nichts wird gesendet") }
        await waitFor(voice, .waiting)
        source.say("Hey Gwen")
        await waitFor(voice, .idle)
        XCTAssertEqual(sent.played, 0, "Abbruchwort und Schweigen schicken nichts ab")
    }

    func testSendingByHandOrWithoutWakeWordPlaysNoSecondTone() async {
        let source = FakeLiveSource()
        let sent = CountingCue()
        let voice = transcriber(source, sent: sent)
        voice.start { _ in }
        await waitFor(voice, .recording)
        source.say("Wie spät ist es Gwen senden")
        voice.listen { _ in }
        await waitFor(voice, .waiting)
        source.say("Hey Gwen Zeig mir den Dom")
        voice.stopAndTranscribe()
        XCTAssertEqual(sent.played, 0, "der Ton gehört nur zum Weckwort und zum automatischen Absenden")
    }

    func testRecordingByHandPlaysNoGreeting() async {
        let source = FakeLiveSource()
        let cue = CountingCue()
        let voice = transcriber(source, cue: cue)
        voice.start { _ in }
        await waitFor(voice, .recording)
        source.say("Hey Gwen wie spät ist es")
        XCTAssertEqual(cue.played, 0)
    }

    func testNothingSaidAfterTheWakeWordEndsQuietly() async {
        let source = FakeLiveSource()
        let voice = transcriber(source, timing: VoiceTiming(silence: 4, nothingSaid: 0.2, maximum: 180))
        voice.listen { _ in XCTFail("ohne Anfrage wird nichts gesendet") }
        await waitFor(voice, .waiting)
        source.say("Hey Gwen")
        await waitFor(voice, .idle)
        XCTAssertEqual(voice.state, .idle)
        XCTAssertNil(voice.lastError, "im Zuhörmodus ist Schweigen kein Fehler")
    }

    func testTappingStopSendsWhatWasHeardSoFar() async {
        let source = FakeLiveSource()
        let voice = transcriber(source)
        let sent = SentWords()
        voice.start { sent.items.append($0) }
        await waitFor(voice, .recording)
        source.say("Zeig mir Bilder vom Dom")
        voice.stopAndTranscribe()
        XCTAssertEqual(sent.items, ["Zeig mir Bilder vom Dom"])
    }

    func testAnEngineChangeRestartsTheWaitingSession() async {
        let source = FakeLiveSource()
        let voice = transcriber(source)
        voice.listen { _ in }
        await waitFor(voice, .waiting)
        XCTAssertEqual(source.starts, 1)
        voice.restartListening()
        await waitFor(voice, .waiting)
        XCTAssertEqual(source.starts, 2, "nach einem Gerätewechsel hört eine neue Sitzung zu")
        XCTAssertTrue(source.isCapturing)
        source.say("Hey Gwen wie spät ist es")
        XCTAssertEqual(voice.state, .recording, "die neue Sitzung erkennt das Weckwort")
    }

    func testARestartLeavesARunningRequestAlone() async {
        let source = FakeLiveSource()
        let voice = transcriber(source)
        let sent = SentWords()
        voice.listen { sent.items.append($0) }
        await waitFor(voice, .waiting)
        source.say("Hey Gwen wie spät ist es")
        await waitFor(voice, .recording)
        voice.restartListening()
        XCTAssertEqual(source.starts, 1, "eine laufende Anfrage wird nicht unterbrochen")
        XCTAssertEqual(voice.state, .recording)
        source.say("Hey Gwen wie spät ist es Gwen senden")
        XCTAssertEqual(sent.items, ["wie spät ist es"])
    }
}

final class DictationSettingsTests: GwenTestCase {
    @MainActor func testUnknownStoredValuesFallBackToTheDefaults() {
        XCTAssertEqual(AppSettings.validChoice(nil, choices: AppSettings.dictationLimitChoices,
                                               fallback: AppSettings.defaultDictationLimit), 180)
        XCTAssertEqual(AppSettings.validChoice(90, choices: AppSettings.dictationLimitChoices,
                                               fallback: AppSettings.defaultDictationLimit), 180)
        XCTAssertEqual(AppSettings.validChoice(300, choices: AppSettings.dictationLimitChoices,
                                               fallback: AppSettings.defaultDictationLimit), 300)
        XCTAssertEqual(AppSettings.validChoice(nil, choices: AppSettings.dictationSilenceChoices,
                                               fallback: AppSettings.defaultDictationSilence), 4)
    }

    @MainActor func testTheChoicesCoverShortAndLongDictation() {
        XCTAssertEqual(AppSettings.dictationLimitChoices.first, 60)
        XCTAssertEqual(AppSettings.dictationLimitChoices.last, 300)
        XCTAssertTrue(AppSettings.dictationLimitChoices.contains(180))
        XCTAssertFalse(AppSettings.dictationLimitChoices.contains(600))
        XCTAssertEqual(AppSettings.dictationSilenceChoices.min(), 2)
        XCTAssertTrue(AppSettings.dictationSilenceChoices.contains(4))
    }

    @MainActor func testTheVoiceTimingComesFromTheSettings() {
        let settings = AppSettings.shared
        let limit = settings.voice.dictationLimitSeconds
        let silence = settings.voice.dictationSilenceSeconds
        settings.voice.dictationLimitSeconds = 300
        settings.voice.dictationSilenceSeconds = 6
        XCTAssertEqual(settings.voiceTiming.maximum, 300)
        XCTAssertEqual(settings.voiceTiming.silence, 6)
        XCTAssertEqual(settings.voiceTiming.nothingSaid, VoiceTiming.standard.nothingSaid)
        settings.voice.dictationLimitSeconds = limit
        settings.voice.dictationSilenceSeconds = silence
    }

    @MainActor func testAValueOutsideTheChoicesFallsBackToTheDefault() {
        let settings = AppSettings.shared
        let previous = settings.voice.dictationLimitSeconds
        settings.voice.dictationLimitSeconds = 999
        XCTAssertEqual(settings.voice.dictationLimitSeconds, 180)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: SettingsKey.dictationLimit), 180)
        settings.voice.dictationLimitSeconds = previous
    }
}
