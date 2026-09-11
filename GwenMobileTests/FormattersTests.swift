import XCTest
@testable import GwenMobile

final class FormattersTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    private var noon: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 12
        components.hour = 14; components.minute = 5
        return Calendar(identifier: .gregorian).date(from: components)
            ?? Date(timeIntervalSince1970: 1_800_000_000)
    }

    func testEventDateTimeRoundTripsThroughTheParser() {
        let text = Formatters.eventDateTime(noon)
        XCTAssertEqual(text, "2026-09-12 14:05")
        XCTAssertEqual(Formatters.eventDate(from: text), noon)
        XCTAssertNil(Formatters.eventDate(from: "12.09.2026 14:05"))
        XCTAssertNil(Formatters.eventDate(from: ""))
    }

    func testMachineReadableFormatsAreLocaleIndependent() {
        let stamp = Formatters.fileStamp(noon)
        XCTAssertNotNil(stamp.wholeMatch(of: /^\d{4}-\d{2}-\d{2}-\d{6}$/), stamp)
        XCTAssertEqual(Formatters.planNow(noon), "2026-09-12 14:05 Saturday")
        XCTAssertEqual(Formatters.systemDate(noon), "Saturday, 2026-09-12")
    }

    func testLocalizedFormatsFollowTheAppLanguage() {
        XCTAssertTrue(Formatters.time(noon).contains("14:05"))
        XCTAssertEqual(Formatters.day(noon), "12. September 2026")
        XCTAssertTrue(Formatters.eventStart(noon).hasPrefix("Sa"), Formatters.eventStart(noon))
        XCTAssertTrue(Formatters.eventStart(noon).contains("14:05"), Formatters.eventStart(noon))
        XCTAssertTrue(Formatters.eventStart(noon).contains("2026"), Formatters.eventStart(noon))
        L.apply(.en)
        XCTAssertTrue(Formatters.eventStart(noon).hasPrefix("Sat"), Formatters.eventStart(noon))
        XCTAssertTrue(Formatters.eventStart(noon).contains("2:05 PM"), Formatters.eventStart(noon))
        L.apply(.de)
    }

    func testSamePatternIsCachedNotRebuilt() {
        let first = Formatters.eventDateTime(noon)
        let second = Formatters.eventDateTime(noon)
        XCTAssertEqual(first, second)
    }
}
