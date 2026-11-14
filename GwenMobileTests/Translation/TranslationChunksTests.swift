@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class TranslationChunksTests: XCTestCase {
    func testShortTextStaysOnePiece() {
        XCTAssertEqual(TranslationChunks.split("Hallo Welt, wie geht es dir?"), ["Hallo Welt, wie geht es dir?"])
    }

    func testJoiningThePiecesRestoresTheOriginalExactly() {
        let samples = [
            String(repeating: "Der Text bleibt erhalten. ", count: 120),
            "Erste Zeile\nZweite Zeile\n\nDritte Zeile nach leerer Zeile.",
            "Ein-Wort-ohne-Leerzeichen-" + String(repeating: "abcdefghij", count: 200),
            "Leerzeichen am Ende   \nUnd danach noch was.",
        ]
        for sample in samples {
            let pieces = TranslationChunks.split(sample)
            XCTAssertEqual(pieces.joined(), sample, "zusammengefügt weicht ab bei \(sample.prefix(20))")
            XCTAssertLessThanOrEqual(pieces.max(by: { $0.count < $1.count })?.count ?? 0,
                                     TranslationChunks.limit)
        }
    }

    func testSentencesAreKeptTogetherWhileTheyFit() {
        let pieces = TranslationChunks.split("Kurzer Satz. Noch einer. Drittes Beispiel hier.")
        XCTAssertEqual(pieces.count, 1)
    }

    func testSentencesBecomeTheirOwnSegments() {
        XCTAssertEqual(TranslationChunks.segments("Erster Satz. Zweiter Satz! Dritter Satz?"),
                       ["Erster Satz. ", "Zweiter Satz! ", "Dritter Satz?"])
    }

    func testSpacesAfterATerminatorStayWithTheSentenceTheyClose() {
        XCTAssertEqual(TranslationChunks.segments("Erster Satz.   Zweiter Satz."),
                       ["Erster Satz.   ", "Zweiter Satz."])
    }

    func testLongRunningTextIsCutAlongSentenceEnds() {
        let text = (1...90).map { "Das ist ein ziemlich langer Satz Nummer \(String($0))." }
            .joined(separator: " ")
        let pieces = TranslationChunks.split(text)
        XCTAssertGreaterThan(pieces.count, 1, "der Text liegt über dem Stücklimit")
        XCTAssertTrue(pieces.dropLast().allSatisfy {
            $0.trimmed.hasSuffix(".")
        }, "kein Stück endet mitten im Satz")
        XCTAssertEqual(pieces.joined(), text)
    }

    func testNewlineStartsANewSegment() {
        let long = String(repeating: "Wort ", count: 250)
        let pieces = TranslationChunks.split(long + "\n" + long)
        XCTAssertGreaterThanOrEqual(pieces.count, 3)
        XCTAssertTrue(pieces.contains { $0.contains("\n") })
    }

    func testHardSplitBreaksAtSpacesAndNeverLosesCharacters() {
        let text = (1...400).map { "wort\($0)" }.joined(separator: " ")
        let pieces = TranslationChunks.hardSplit(text)
        XCTAssertEqual(pieces.joined(), text)
        XCTAssertTrue(pieces.allSatisfy { $0.count <= TranslationChunks.limit })
    }

    func testPackAddsNothingBetweenPieces() {
        XCTAssertEqual(TranslationChunks.pack(["a ", "b ", "c"]), ["a b c"])
    }
}
