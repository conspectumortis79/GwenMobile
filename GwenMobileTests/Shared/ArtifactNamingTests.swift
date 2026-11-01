@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ArtifactNamingTests: GwenTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_800_000_000)

    func testTitleIsTheQuestionWithoutPunctuation() {
        XCTAssertEqual(ArtifactNaming.title(from: "Wie viele Arbeitslose gab es?!"),
                       "Wie viele Arbeitslose gab es")
        XCTAssertEqual(ArtifactNaming.title(from: "Erkläre „Klima\u{2009}–\u{2009}erwärmung\" bitte! 🌍"),
                       "Erkläre Klima erwärmung bitte")
        XCTAssertEqual(ArtifactNaming.title(from: "   "), "")
        XCTAssertEqual(ArtifactNaming.title(from: nil), "")
    }

    func testTitleKeepsTheFirstWordsOnly() {
        let long = "a b c d e f g h i j k l"
        XCTAssertEqual(ArtifactNaming.title(from: long), "a b c d e f g h i")
        XCTAssertEqual(ArtifactNaming.title(from: long).split(separator: " ").count,
                       ArtifactNaming.maxTitleWords)
        let giant = String(repeating: "a", count: ArtifactNaming.maxTitleChars * 4)
        XCTAssertEqual(ArtifactNaming.title(from: giant).count, ArtifactNaming.maxTitleChars)
    }

    func testNameCarriesTheExtensionAndFallsBackToTheTimestamp() {
        let naming = ArtifactNaming(directory: URL(fileURLWithPath: "/tmp"), fileExtension: "html",
                                   fallbackPrefix: "antwort")
        XCTAssertEqual(naming.name(from: "Was ist die Hauptstadt von Frankreich?", date: stamp),
                       "Was ist die Hauptstadt von Frankreich.html")
        let fallback = naming.name(from: "!!! ???", date: stamp)
        XCTAssertTrue(fallback.hasPrefix("antwort-"), fallback)
        XCTAssertTrue(fallback.hasSuffix(".html"), fallback)
        XCTAssertNotNil(fallback.wholeMatch(of: /^antwort-\d{4}-\d{2}-\d{2}-\d{6}\.html$/), fallback)
    }

    func testUniqueNameNeverReplacesWhatIsAlreadyThere() throws {
        let directory = tempDocuments()
        let naming = ArtifactNaming(directory: directory, fileExtension: "html", fallbackPrefix: "antwort")
        let wanted = naming.name(from: "Gleiche Frage?", date: stamp)
        XCTAssertEqual(wanted, "Gleiche Frage.html")
        XCTAssertFalse(naming.uniqueName(from: "Gleiche Frage?", date: stamp).contains("2"))
        try "x".write(to: naming.url(named: wanted), atomically: true, encoding: .utf8)
        XCTAssertEqual(naming.uniqueName(from: "Gleiche Frage?", date: stamp), "Gleiche Frage 2.html")
        try "y".write(to: naming.url(named: "Gleiche Frage 2.html"), atomically: true, encoding: .utf8)
        XCTAssertEqual(naming.uniqueName(from: "Gleiche Frage?", date: stamp), "Gleiche Frage 3.html")
    }

    func testTheNamedURLStaysInsideItsOwnDirectory() {
        let directory = tempDocuments()
        let naming = ArtifactNaming(directory: directory, fileExtension: "py", fallbackPrefix: "code")
        XCTAssertEqual(naming.url(named: "zähler.py").path,
                       directory.appendingPathComponent("zähler.py").path)
    }

    func testAfterNineHundredNinetyNineCollisionsTheStampedFallbackWins() throws {
        let directory = tempDocuments()
        let naming = ArtifactNaming(directory: directory, fileExtension: "html", fallbackPrefix: "antwort")
        try Data().write(to: naming.url(named: "Protokoll.html"))
        for index in 2...999 {
            try Data().write(to: naming.url(named: "Protokoll \(index).html"))
        }
        let name = naming.uniqueName(from: "Protokoll", date: stamp)
        XCTAssertTrue(name.hasPrefix("antwort-"), name)
    }
}
