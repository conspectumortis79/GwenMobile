@testable import GwenMobileFeatureCore
import XCTest

final class PriceBadgeTests: GwenTestCase {
    private let old = Data([0xFF, 0xD8, 0xFF, 0x01])
    private let fresh = Data([0xFF, 0xD8, 0xFF, 0x02])

    private func routed(_ turn: ModelTurn, _ attachments: [Attachment]) -> RoutedSend {
        RoutedSend(text: "was ist das günstigste MacBook 13",
                   plan: SendPlan.singleChat, turn: turn, history: [],
                   attachments: attachments, files: [], convID: UUID(), started: Date())
    }

    func testOnlyAPictureOfThisMessageCountsAsAnAttachment() {
        let turn = ModelTurn(messages: [], images: [old, fresh], pictureFiles: ["img_alt.jpg", "img_neu.jpg"])
        XCTAssertEqual(routed(turn, [Attachment(file: "img_neu.jpg")]).attachedPictures, [fresh])
    }

    func testARememberedPictureStaysOutOfTheAttachmentPictures() {
        let turn = ModelTurn(messages: [], images: [old], pictureFiles: ["img_alt.jpg"])
        XCTAssertTrue(routed(turn, []).attachedPictures.isEmpty,
                      "ohne Anhang darf kein Lese-Badge erscheinen")
        XCTAssertTrue(routed(ModelTurn(messages: [], images: []), []).attachedPictures.isEmpty)
    }

    func testEveryPictureOfThisMessageTravelsWithTheAttachment() {
        let turn = ModelTurn(messages: [], images: [old, fresh], pictureFiles: ["a.jpg", "b.jpg"])
        let both = routed(turn, [Attachment(file: "a.jpg"), Attachment(file: "b.jpg")])
        XCTAssertEqual(both.attachedPictures, [old, fresh])
    }
}
