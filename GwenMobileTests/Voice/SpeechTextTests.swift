@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class SpeechTextTests: GwenTestCase {
    func testFootnoteMarkersNeverReachTheVoice() {
        let spoken = SpeechSynthesizer.stripForSpeech(
            "Angriffe auf Kiew: mindestens 7 Tote gemeldet [5][1]. Die Lage bleibt angespannt [12].")
        XCTAssertEqual(spoken, "Angriffe auf Kiew: mindestens 7 Tote gemeldet. Die Lage bleibt angespannt.")
    }

    func testAMarkerInsideASentenceLeavesOneCleanSpace() {
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("Quelle [3] nennt 465,8 Mrd. kWh"),
                       "Quelle nennt 465,8 Mrd. kWh")
    }

    func testMarkersOnTheirOwnLineKeepTheLineBreak() {
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("- Punkt eins [1]\n- Punkt zwei [2]"),
                       "- Punkt eins\n- Punkt zwei")
    }

    func testGroupedMarkersNeverReachTheVoice() {
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("Kernfusion setzt Energie frei [1, 3, 4]."),
                       "Kernfusion setzt Energie frei.")
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("Beides ist belegt [1;2]."),
                       "Beides ist belegt.")
    }

    func testHeadingMarksDisappearOnEveryLine() {
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("## Überblick\nErster Satz.\n## Details\nZweiter Satz."),
                       "Überblick\nErster Satz.\nDetails\nZweiter Satz.")
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("\n### Nächster Punkt\nText"), "Nächster Punkt\nText")
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("Programmieren in C# macht Spaß"),
                       "Programmieren in C# macht Spaß")
    }

    func testAnAnswerThatIsOnlyAMarkerSpeaksNothing() {
        XCTAssertTrue(SpeechSynthesizer.stripForSpeech("[1]").isEmpty)
    }

    func testZeroIndexedTextSurvivesBecauseCitationsStartAtOne() {
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("Das Feld data[0] bleibt erhalten"),
                       "Das Feld data[0] bleibt erhalten")
    }

    func testBoldCodeAndLinksStillDisappear() {
        let spoken = SpeechSynthesizer.stripForSpeech(
            "**Hauptstadt** `Paris`\n```python\nprint(1)\n```\nhttps://example.de")
        XCTAssertFalse(spoken.contains("**"))
        XCTAssertFalse(spoken.contains("```"))
        XCTAssertFalse(spoken.contains("http"))
        XCTAssertTrue(spoken.contains("Paris"))
    }

    func testAMarkedPhoneNumberIsSpokenAsItsPlainNumber() {
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("Ruf [030 1234567](tel:+49301234567) an."),
                       "Ruf 030 1234567 an.")
    }

    func testALabeledWebLinkIsSpokenAsItsLabel() {
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("Mehr in [Wikipedia](https://example.com/x)."),
                       "Mehr in Wikipedia.")
    }

    func testEmojiNeverReachTheVoiceAsTheirOwnName() {
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("🔊 Vorlesen ist jetzt an"), "Vorlesen ist jetzt an")
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("🔇 Vorlesen ist jetzt aus."), "Vorlesen ist jetzt aus.")
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("✔ Erinnerung angelegt: Zahnarzt"),
                       "Erinnerung angelegt: Zahnarzt")
        XCTAssertEqual(SpeechSynthesizer.stripForSpeech("📍 beim Ankommen: REWE"), "beim Ankommen: REWE")
    }

    func testAnAnswerThatIsOnlyAnEmojiSpeaksNothing() {
        XCTAssertTrue(SpeechSynthesizer.stripForSpeech("🔊").isEmpty)
        XCTAssertTrue(SpeechSynthesizer.stripForSpeech("✔️").isEmpty)
    }
}
