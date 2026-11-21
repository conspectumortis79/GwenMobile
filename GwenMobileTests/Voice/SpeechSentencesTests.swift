@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SpeechSentencesTests: GwenTestCase {
    func testASentenceIsTakenAfterItsTerminator() {
        var buffer = "Das ist der erste Satz der Antwort. Und der zweite"
        XCTAssertEqual(SpeechSentences.take(from: &buffer), ["Das ist der erste Satz der Antwort."])
        XCTAssertEqual(buffer, " Und der zweite")
    }

    func testATrailingTerminatorWaitsForMoreText() {
        var buffer = "Das ist der erste Satz der Antwort."
        XCTAssertEqual(SpeechSentences.take(from: &buffer), [])
        XCTAssertEqual(buffer, "Das ist der erste Satz der Antwort.")
    }

    func testAShortFragmentWaitsForTheNextSentence() {
        var buffer = "Ja. Das ist der erste Satz der Antwort. Noch"
        XCTAssertEqual(SpeechSentences.take(from: &buffer), ["Ja. Das ist der erste Satz der Antwort."])
        XCTAssertEqual(buffer, " Noch")
    }

    func testAnAbbreviationDoesNotEndASentence() {
        var buffer = "Das ist ein wirklich langer Satz, z. B. mit Beispiel. Noch"
        XCTAssertEqual(SpeechSentences.take(from: &buffer),
                       ["Das ist ein wirklich langer Satz, z. B. mit Beispiel."])
    }

    func testANumberBeforeTheDotDoesNotEndASentence() {
        var buffer = "Wir brauchen eine Zahl, naemlich 3. Danach folgt der naechste Satz. Noch"
        XCTAssertEqual(SpeechSentences.take(from: &buffer),
                       ["Wir brauchen eine Zahl, naemlich 3. Danach folgt der naechste Satz."])
    }

    func testAnOpenCodeFenceHoldsTheSentenceBack() {
        var buffer = "Hier beginnt ein Abschnitt mit Code ```let wert = 1"
        XCTAssertEqual(SpeechSentences.take(from: &buffer), [])
        buffer += "``` und danach folgt der naechste Satz. Noch"
        XCTAssertEqual(SpeechSentences.take(from: &buffer),
                       ["Hier beginnt ein Abschnitt mit Code ```let wert = 1``` und danach folgt der naechste Satz."])
    }

    func testAParagraphBreakEndsASentence() {
        var buffer = "Ein kurzer Abschnitt der Antwort\n\nDer naechste Abschnitt"
        XCTAssertEqual(SpeechSentences.take(from: &buffer), ["Ein kurzer Abschnitt der Antwort\n\n"])
        XCTAssertEqual(buffer, "Der naechste Abschnitt")
    }

    func testQuestionAndExclamationEndASentence() {
        var buffer = "Ist das die erste Frage der Antwort? Ja, das ist die zweite Frage der Antwort! Noch"
        XCTAssertEqual(SpeechSentences.take(from: &buffer),
                       ["Ist das die erste Frage der Antwort?", " Ja, das ist die zweite Frage der Antwort!"])
        XCTAssertEqual(buffer, " Noch")
    }
}

extension SpeechSentencesTests {
    func testSingleNewlinesAndNonWhitespaceFollowersDoNotCut() {
        var single = "Ein langer Satz der Antwort steht hier\nund laeuft weiter"
        XCTAssertTrue(SpeechSentences.take(from: &single).isEmpty)
        XCTAssertEqual(single, "Ein langer Satz der Antwort steht hier\nund laeuft weiter")
        var shortBreak = "\n\nx"
        XCTAssertTrue(SpeechSentences.take(from: &shortBreak).isEmpty)
        var glued = "Das ist ein wirklich langer Satz der Antwort.X"
        XCTAssertTrue(SpeechSentences.take(from: &glued).isEmpty)
        XCTAssertEqual(glued, "Das ist ein wirklich langer Satz der Antwort.X")
    }
}
