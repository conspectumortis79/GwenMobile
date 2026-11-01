@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class FormattersTests: GwenTestCase {
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

    func testStampIsTheMachineReadableDay() {
        XCTAssertEqual(Formatters.stamp(noon), "2026-09-12")
        XCTAssertEqual(Formatters.eventDay(from: Formatters.stamp(noon)) != nil, true)
    }

    func testIsoDatesParseWithAndWithoutFractionalSeconds() {
        XCTAssertEqual(Formatters.isoDate(from: "2026-09-12T14:05:00Z")?.timeIntervalSince1970 ?? 0,
                       1_789_221_900, accuracy: 0.001)
        XCTAssertEqual(Formatters.isoDate(from: "2026-09-12T14:05:00.250Z")?.timeIntervalSince1970 ?? 0,
                       1_789_221_900.25, accuracy: 0.001)
        XCTAssertNil(Formatters.isoDate(from: "2026-09-12"))
    }

    func testLocalizedFormatsFollowTheAppLanguage() {
        L.apply(.en)
        XCTAssertTrue(Formatters.time(noon).contains("2:05 PM"))
        XCTAssertEqual(Formatters.day(noon), "September 12, 2026")
        XCTAssertTrue(Formatters.eventStart(noon).hasPrefix("Sat"), Formatters.eventStart(noon))
        XCTAssertTrue(Formatters.eventStart(noon).contains("2:05 PM"), Formatters.eventStart(noon))
        XCTAssertTrue(Formatters.eventStart(noon).contains("2026"), Formatters.eventStart(noon))
        L.apply(.de)
        XCTAssertTrue(Formatters.time(noon).contains("14:05"))
        XCTAssertEqual(Formatters.day(noon), "12. September 2026")
        XCTAssertTrue(Formatters.eventStart(noon).hasPrefix("Sa"), Formatters.eventStart(noon))
        XCTAssertTrue(Formatters.eventStart(noon).contains("14:05"), Formatters.eventStart(noon))
        L.apply(.en)
    }

    func testSamePatternIsCachedNotRebuilt() {
        let first = Formatters.eventDateTime(noon)
        let second = Formatters.eventDateTime(noon)
        XCTAssertEqual(first, second)
    }
}

final class FormattersThreadSafetyTests: GwenTestCase {
    func testConcurrentRenderingOfTheSamePatternAlwaysAgrees() async {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let expected = Formatters.time(date)
        let expectedDay = Formatters.day(date)
        let observed = LockedValue([String]())
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask(priority: .userInitiated) {
                    for _ in 0..<250 {
                        observed.mutate { seen in
                            seen.append(Formatters.time(date) == expected ? "z" : "a")
                            seen.append(Formatters.day(date) == expectedDay ? "z" : "a")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(Set(observed.current), ["z"], "jede nebenläufige Ausgabe muss mit dem Alleinlauf übereinstimmen")
        XCTAssertEqual(observed.current.count, 4000)
    }

    func testRelationalDaysNameTodayAndYesterday() {
        XCTAssertEqual(Formatters.relationalDay(Date()), L.t("today"))
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        XCTAssertEqual(Formatters.relationalDay(yesterday), L.t("yesterday"))
        let older = calendar.date(byAdding: .day, value: -5, to: Date()) ?? Date()
        XCTAssertEqual(Formatters.relationalDay(older), Formatters.day(older))
    }

    func testPricesAndCountsFollowTheAppLanguage() {
        L.apply(.de)
        XCTAssertTrue(Formatters.price(429.99, currency: "EUR").contains("429,99"))
        XCTAssertTrue(Formatters.price(429.99, currency: "EUR").contains("€"))
        XCTAssertTrue(Formatters.price(429.99, currency: nil).contains("429,99"))
        XCTAssertTrue(Formatters.price(429.99, currency: "").contains("429,99"))
        XCTAssertEqual(Formatters.countText(1234).filter(\.isNumber), "1234")
        L.apply(.en)
        XCTAssertTrue(Formatters.price(429.99, currency: nil).contains("429.99"))
        XCTAssertTrue(Formatters.countText(1234).contains("1,234"))
    }
}
