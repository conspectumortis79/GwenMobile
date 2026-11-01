@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import UIKit
import GwenMobileKit

@MainActor
final class PendingPictureTests: XCTestCase {
    private func batch(_ count: Int) -> [PendingPicture] {
        (0..<count).map { _ in PendingPicture(image: FakePicture.make(), file: nil) }
    }

    func testAddingUpToTheLimitKeepsEverythingAndDropsNothing() {
        let outcome = ChatView.keeping(batch(6), alongside: batch(4))
        XCTAssertEqual(outcome.kept.count, 10)
        XCTAssertEqual(outcome.fresh.count, 6)
        XCTAssertEqual(outcome.dropped, 0)
    }

    func testMorePicturesThanTheRoomAllowsReportExactlyWhatFellOutOfTheMessage() {
        let added = batch(8)
        let outcome = ChatView.keeping(added, alongside: batch(7))
        XCTAssertEqual(outcome.kept.count, ImagePolicy.maxAttachmentsPerMessage)
        XCTAssertEqual(outcome.fresh.count, 3, "nur drei der acht neuen schaffen es daneben")
        XCTAssertEqual(outcome.dropped, 5)
        XCTAssertEqual(outcome.fresh.map(\.id), Array(added.prefix(3)).map(\.id),
                       "es fallen die letzten weg, nicht beliebige")
    }

    func testAChatThatIsAlreadyFullDropsTheWholeNewBatch() {
        let outcome = ChatView.keeping(batch(2), alongside: batch(10))
        XCTAssertTrue(outcome.fresh.isEmpty)
        XCTAssertEqual(outcome.dropped, 2)
        XCTAssertEqual(outcome.kept.count, 10)
    }
}

final class CarriedFileTests: GwenTestCase {
    private func file(_ name: String, _ stored: String, chars: Int = 400) -> AttachedFile {
        AttachedFile(file: stored, name: name, kind: .pdf, bytes: 1_000, chars: chars, via: .textLayer)
    }

    func testAFileThatDidNotFitIntoTheContextIsNotListedAsASourceOfTheAnswer() {
        let big = String(repeating: "z", count: FilePolicy.maxContextChars)
        let history = [ChatMessage(role: .user, text: "Zwei Dateien",
                                   files: [file("alt.pdf", "doc_old.pdf", chars: big.count),
                                           file("neu.pdf", "doc_new.pdf", chars: 20)])]
        let texts: [String: String] = ["doc_old.pdf": big, "doc_new.pdf": "kurzer inhalt"]
        let turn = ConversationMemory.turn(from: history, load: { _ in nil },
                                           fileText: { texts[$0] })
        XCTAssertEqual(turn.carriedFileNames, ["neu.pdf"])
        let refs = ChatView.fileRefs(from: history, carried: turn.carriedFileNames)
        XCTAssertEqual(refs.map(\.name), ["neu.pdf"],
                       "der Chip unter der Antwort nennt nur, was das Modell wirklich las")
        XCTAssertTrue(turn.messages.last!.text.contains(FileTextBlocks.omittedNotice(1)))
        XCTAssertEqual(ChatView.fileRefs(from: history, carried: nil).map(\.name), ["alt.pdf", "neu.pdf"],
                       "ohne Kenntnis des Turns bleiben alle lesbaren Dateien gelistet")
    }
}

final class PictureOutOfReachWordTests: GwenTestCase {
    func testALeftOutPictureIsNamedAsBudgetAndNotAsAMiss() {
        let notice = ChatView.unreachablePictureNotice(leftBehind: 4)
        XCTAssertTrue(notice.contains("4"), notice)
        XCTAssertTrue(notice.contains(String(ConversationMemory.maxPictures)), notice)
    }

    func testNothingMatchingSaysSoInsteadOfBlamingTheBudget() {
        let notice = ChatView.unreachablePictureNotice(leftBehind: 0)
        XCTAssertEqual(notice, L.t("picture_nothing_matches"), notice)
        XCTAssertFalse(notice.contains("ältere Bilder"), notice)
        XCTAssertFalse(notice.contains("%@"), notice)
    }
}
