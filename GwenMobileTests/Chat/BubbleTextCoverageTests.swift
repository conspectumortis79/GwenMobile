@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class BubbleTextCoverageTests: GwenTestCase {
    private func makeBubble(_ text: String, user: Bool = false, streaming: Bool = false,
                            sources: [WebSource] = [], review: SourceReview? = nil) -> Bubble {
        let paths = temporaryPaths("bubble-text")
        var message = ChatMessage(role: user ? .user : .assistant, text: text)
        message.sources = sources
        message.sourceReview = review
        var bubble = Bubble(message: message, media: MediaStore(paths: paths),
                            photos: PhotoLibraryWriter())
        bubble.streaming = streaming
        return bubble
    }

    private func review() -> SourceReview {
        var review = SourceReview()
        review.sourceDomains = 3
        review.sourceGroups = [[1, 2], [3]]
        review.citedSources = 3
        review.citedOrigins = 2
        review.citedClaims = 2
        review.crossChecked = true
        review.checkedClaims = 2
        review.results = [SourceReview.ClaimResult(claim: "Eine unbelegte Aussage", verdict: .unsupported,
                                                   sources: [2], contradicts: []),
                          SourceReview.ClaimResult(claim: "Eine widerlegte Aussage", verdict: .contradicted,
                                                   sources: [1], contradicts: [2])]
        return review
    }

    func testTheAttributedAnswerRenderers() {
        let source = WebSource(title: "Quelle", url: "https://q.test/a", domain: "q.test")
        let bubble = makeBubble("Antwort mit **fett** und `code` und [1]",
                                sources: [source, source, source], review: review())
        let attributed = bubble.answerAttributedString(for: "Antwort mit **fett** und `code` und [1]")
        XCTAssertFalse(String(attributed.characters).isEmpty)
        let second = bubble.answerAttributedString(for: "Antwort mit **fett** und `code` und [1]")
        XCTAssertEqual(String(second.characters), String(attributed.characters))
        XCTAssertFalse(bubble.reviewKey(bubble.sourceReview).isEmpty)
        XCTAssertFalse(bubble.signatureLine(model: "qwen").isEmpty)
        let plain = makeBubble("Nur Text")
        XCTAssertEqual(plain.reviewKey(nil), "")
        _ = plain.rendered("**x**")
        let streaming = makeBubble("halb", streaming: true)
        XCTAssertFalse(String(streaming.answerAttributedString(for: "halb").characters).isEmpty)
        XCTAssertFalse(streaming.answerParts.isEmpty)
    }

    func testTheClaimMarksAndHandlers() {
        let review = review()
        let answer = "Eine unbelegte Aussage [2] und eine widerlegte Aussage [1]."
        XCTAssertFalse(review.marks(in: answer).isEmpty)
        let bubble = makeBubble(answer, sources: [WebSource(title: "A", url: "https://a.test",
                                                            domain: "a.test")],
                                review: review)
        let attributed = bubble.markedAnswer(AttributedString(answer), review: review)
        XCTAssertFalse(String(attributed.characters).isEmpty)
        let unsupported = bubble.claimMarker(SourceReview.ClaimMark(
            range: answer.startIndex..<answer.index(answer.startIndex, offsetBy: 5), resultIndex: 0,
            verdict: .unsupported))
        XCTAssertFalse(String(unsupported.characters).isEmpty)
        let contradicted = bubble.claimMarker(SourceReview.ClaimMark(
            range: answer.startIndex..<answer.index(answer.startIndex, offsetBy: 5), resultIndex: 1,
            verdict: .contradicted))
        XCTAssertFalse(String(contradicted.characters).isEmpty)
        _ = bubble.claimColour(.unsupported)
        _ = bubble.claimColour(.contradicted)
        _ = bubble.bubbleColor
    }

    func testTheURLHandling() {
        let bubble = makeBubble("Antwort")
        XCTAssertNil(Bubble.telNumber(of: URL(string: "https://example.test")!))
        let tel = Bubble.telNumber(of: URL(string: "tel:+49%20123")!)
        XCTAssertEqual(tel?.digits, "+49123")
        XCTAssertTrue(Bubble.telNumber(of: URL(string: "tel:00123")!) != nil)
        var called: DialNumber?
        var withCall = bubble
        withCall.onCall = { number in called = number }
        XCTAssertTrue(withCall.handleAnswerURL(URL(string: "tel:12345")!))
        XCTAssertEqual(called?.digits, "12345")
        XCTAssertFalse(bubble.handleAnswerURL(URL(string: "https://example.test/x")!))
        _ = bubble.answerOpener
    }

    func testTheFileHelpers() {
        let paths = temporaryPaths("bubble-files")
        var message = ChatMessage(role: .assistant, text: "Dateien")
        message.fileRefs = [FileRef(name: "Anhang.docx", detail: "2 Seiten", via: .docx),
                            FileRef(name: "eins.pdf", detail: nil, via: .ocr)]
        message.ocrFiles = [OcrFile(file: "ocr/a.jpg", chars: 12)]
        let bubble = Bubble(message: message, media: MediaStore(paths: paths),
                            photos: PhotoLibraryWriter())
        XCTAssertEqual(bubble.extractionKey, "file_local_docx")
        XCTAssertTrue(bubble.liveOCRFiles.isEmpty)
        XCTAssertEqual(Bubble.savedLine(.saved(1)), L.t("image_saved"))
        XCTAssertEqual(Bubble.savedLine(.saved(3)), L.n("pictures_saved_all", 3))
        XCTAssertEqual(Bubble.savedLine(.denied), L.t("photos_not_allowed"))
        XCTAssertFalse(Bubble.savedLine(.failed).isEmpty)
    }
}
