@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class NoticeLineTests: GwenTestCase {
    func testANoteAppearsWhenShownAndDisappearsAfterItsLifetime() async {
        let notice = NoticeLine(lifetime: .milliseconds(80))
        XCTAssertNil(notice.text)
        notice.show("✔ Gesichert")
        XCTAssertEqual(notice.text, "✔ Gesichert")
        await waitUntil { notice.text == nil }
    }

    func testTheNewestNoteReplacesTheOldOneAndRestartsItsLifetime() async {
        let notice = NoticeLine(lifetime: .milliseconds(600))
        notice.show("erste")
        notice.show("zweite")
        XCTAssertEqual(notice.text, "zweite")
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(notice.text, "zweite", "die zweite Note zählt von vorn, die erste löscht nichts mehr")
    }
}
