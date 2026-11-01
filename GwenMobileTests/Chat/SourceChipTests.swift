@testable import GwenMobileAdapters
import XCTest
import GwenMobileKit

final class SourceChipTests: XCTestCase {
    func testTheShortNameIsTheMainPartOfTheDomain() {
        XCTAssertEqual(SourceChip.shortName("de.wikipedia.org"), "wikipedia")
        XCTAssertEqual(SourceChip.shortName("www.spiegel.de"), "spiegel")
        XCTAssertEqual(SourceChip.shortName("gala.de"), "gala")
    }

    func testACountrySecondLevelIsSkippedForTheShortName() {
        XCTAssertEqual(SourceChip.shortName("bbc.co.uk"), "bbc")
        XCTAssertEqual(SourceChip.shortName("news.abc.net.au"), "abc")
        XCTAssertEqual(SourceChip.shortName("cinema.co"), "cinema")
    }

    func testANameWithoutDotsStaysAsItIs() {
        XCTAssertEqual(SourceChip.shortName("localhost"), "localhost")
        XCTAssertEqual(SourceChip.shortName(""), "")
    }

    func testOnlyLongNamesAreCut() {
        XCTAssertFalse(SourceChip.needsCut("gala"))
        XCTAssertFalse(SourceChip.needsCut("imdb"))
        XCTAssertTrue(SourceChip.needsCut("hellomagazine"))
        XCTAssertTrue(SourceChip.needsCut("rollingstone"))
    }
}
