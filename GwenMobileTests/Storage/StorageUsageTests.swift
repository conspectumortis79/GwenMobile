@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class StorageUsageTests: GwenTestCase {
    func testTheUsageLinesDescribeTheCounts() {
        var usage = StorageUsage()
        usage.conversations = 2
        usage.messages = 5
        usage.imageFiles = 3
        usage.imageBytes = 2048
        usage.documentFiles = 1
        usage.documentBytes = 1024
        XCTAssertEqual(usage.imageBytesText, StorageUsage.bytesText(2048))
        XCTAssertEqual(usage.documentBytesText, StorageUsage.bytesText(1024))
        XCTAssertEqual(usage.attachmentsBytes, 3072)
        XCTAssertEqual(usage.summaryText, "4 · \(StorageUsage.bytesText(3072))")
        XCTAssertTrue(usage.imagesLine.contains("3"), usage.imagesLine)
        XCTAssertTrue(usage.documentsLine.contains("1"), usage.documentsLine)
        XCTAssertEqual(usage.exportsLine, "")
        XCTAssertTrue(usage.historyLine.contains("2"), usage.historyLine)
        XCTAssertTrue(usage.headerLine.contains(usage.imageBytesText), usage.headerLine)
        XCTAssertFalse(usage.deleteAllBody.isEmpty)
        usage.exportFiles = 2
        usage.exportBytes = 4096
        XCTAssertEqual(usage.exportBytesText, StorageUsage.bytesText(4096))
        XCTAssertFalse(usage.exportsLine.isEmpty)
        XCTAssertTrue(usage.deleteAllBody.contains(usage.documentsLine), usage.deleteAllBody)
        usage.documentFiles = 0
        usage.documentBytes = 0
        XCTAssertFalse(usage.headerLine.contains(usage.documentBytesText), usage.headerLine)
    }

    func testOverflowingByteSumsSaturateInsteadOfTrapping() {
        var usage = StorageUsage()
        usage.imageBytes = Int.max
        usage.documentBytes = 1
        XCTAssertEqual(usage.attachmentsBytes, Int.max)
    }
}
