import XCTest
@testable import GwenMobile

final class PictureOrdinalsTests: XCTestCase {
    func testGermanOrdinalsFindTheChatPlacesInReadingOrder() {
        XCTAssertEqual(PictureOrdinals.places(in: "Ändere die Farbe des ersten Fotos in die Farbe des dritten Fotos.",
                                              total: 5), [1, 3])
        XCTAssertEqual(PictureOrdinals.places(in: "Mache den Gegenstand aus dem vierten Foto genau so groß wie den Gegenstand aus dem ersten Foto.",
                                              total: 4), [4, 1])
        XCTAssertEqual(PictureOrdinals.places(in: "Nimm den Hintergrund aus dem zweiten Bild und gib das vierte Bild damit wieder.",
                                              total: 4), [2, 4])
    }

    func testEnglishOrdinalsAndPictureNounsAreUnderstood() {
        XCTAssertEqual(PictureOrdinals.places(in: "Take the colour of photo 2 to photo 1.", total: 3), [2, 1])
        XCTAssertEqual(PictureOrdinals.places(in: "paint the third picture blue", total: 4), [3])
    }

    func testWordsThatDoNotNameAPictureStayUnresolved() {
        XCTAssertEqual(PictureOrdinals.places(in: "Gib mir einen zweiten Kaffee.", total: 4), [])
        XCTAssertEqual(PictureOrdinals.places(in: "Der zweite Hinweis soll eine Stunde vorher kommen.", total: 4), [])
        XCTAssertEqual(PictureOrdinals.places(in: "", total: 4), [])
    }

    func testAmbiguousMentionsAreNotResolvedAtAll() {
        XCTAssertEqual(PictureOrdinals.places(in: "Das dritte Foto, noch einmal das dritte Foto.", total: 4), [])
        XCTAssertEqual(PictureOrdinals.places(in: "Vom siebten Foto auf das erste Foto.", total: 4), [])
    }

    func testChatPlaceMapsToTheShownBildNumber() {
        XCTAssertEqual(PictureOrdinals.bild(of: 3, shown: [1, 3, 4, 5]), 2)
        XCTAssertEqual(PictureOrdinals.bild(of: 1, shown: [1, 3, 4, 5]), 1)
        XCTAssertNil(PictureOrdinals.bild(of: 2, shown: [1, 3, 4, 5]))
        XCTAssertTrue(PictureOrdinals.outOfSelection(places: [2], shown: [1, 3, 4, 5]))
        XCTAssertFalse(PictureOrdinals.outOfSelection(places: [3, 5], shown: [1, 3, 4, 5]))
    }

    func testHintNamesEveryMentionedPictureAndNothingWhenOneIsMissing() {
        let hint = PictureOrdinals.hint(places: [1, 3], shown: [1, 3, 4, 5]) ?? ""
        XCTAssertTrue(hint.contains("Chat-Platz 1 = BILD 1"))
        XCTAssertTrue(hint.contains("Chat-Platz 3 = BILD 2"))
        XCTAssertTrue(PictureOrdinals.hint(places: [1, 2], shown: [1, 3, 4, 5]) == nil)
        XCTAssertTrue(PictureOrdinals.hint(places: [4], shown: [1, 4])!.contains("BILD 2"))
    }

    func testBindingHintIsStrongerThanThePlainOne() {
        let plain = PictureOrdinals.hint(places: [3], shown: [1, 3, 4]) ?? ""
        let binding = PictureOrdinals.hint(places: [3], shown: [1, 3, 4], binding: true) ?? ""
        XCTAssertTrue(binding.hasPrefix(plain.replacingOccurrences(of: " Ignoriere jede andere Reihenfolge-Deutung.", with: "")))
        XCTAssertTrue(binding.contains("ausschließlich"))
    }
}
