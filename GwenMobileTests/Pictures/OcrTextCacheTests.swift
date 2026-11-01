@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class OcrTextCacheTests: XCTestCase {
    func testRememberedTextIsReadByItsPictureName() {
        let cache = OcrTextCache()
        cache.remember("  KAFFEE 14,80  ", for: "text_a.jpg.txt")
        XCTAssertEqual(cache.text(for: "text_a.jpg.txt"), "  KAFFEE 14,80  ")
        XCTAssertNil(cache.text(for: "text_b.jpg.txt"))
    }

    func testScanningTheSamePictureAgainKeepsOneEntryWithTheNewestText() {
        let cache = OcrTextCache()
        cache.remember("erster", for: "text_x.jpg.txt")
        cache.remember("zweiter", for: "text_x.jpg.txt")
        XCTAssertEqual(cache.text(for: "text_x.jpg.txt"), "zweiter")
    }

    func testOldestTextIsDroppedOnceTheBudgetIsFull() {
        let cache = OcrTextCache()
        for index in 0..<OcrTextCache.maximumEntries {
            cache.remember("text \(index)", for: "file_\(index)")
        }
        XCTAssertEqual(cache.text(for: "file_0"), "text 0")
        cache.remember("neu", for: "file_neu")
        XCTAssertNil(cache.text(for: "file_0"))
        XCTAssertEqual(cache.text(for: "file_1"), "text 1")
        XCTAssertEqual(cache.text(for: "file_neu"), "neu")
    }
}
