@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ChainPictureBudgetTests: GwenTestCase {
    func testALongChainKeepsOnlyTheNewestPicturesAndTheirFilesTogether() {
        var turn = ModelTurn(messages: [ChatMessage(role: .user, text: "zwölf Bilder")], images: [])
        for number in 1...12 {
            turn = turn.continuing(after: "", pictures: [Data([UInt8(number)])], files: ["bild\(number).jpg"])
        }
        XCTAssertEqual(turn.images.count, ConversationMemory.maxPictures,
                       "eine Kette schickt nie mehr Bilder mit als der übrige Chat")
        XCTAssertEqual(turn.pictureFiles.first, "bild3.jpg", "die ältesten fallen zuerst heraus")
        XCTAssertEqual(turn.pictureFiles.last, "bild12.jpg")
        XCTAssertEqual(turn.images.first, Data([3]), "Bild und Dateiname bleiben beieinander")
    }

    func testAShortChainKeepsEveryPicture() {
        let turn = ModelTurn(messages: [], images: [Data([1])], pictureFiles: ["a.jpg"])
            .continuing(after: "", pictures: [Data([2])], files: ["b.jpg"])
        XCTAssertEqual(turn.pictureFiles, ["a.jpg", "b.jpg"])
        XCTAssertEqual(turn.images.count, 2)
    }
}

@MainActor
final class ChainContinuationTests: GwenTestCase {
    func testAPictureThatCannotBeLoadedTakesItsFileNameWithIt() async throws {
        let media = scratchMediaStore()
        guard let kept = media.storeImageData(FakePictureData.jpeg()) else { return XCTFail("kein Bild") }
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "",
                              artifacts: AnswerArtifacts(outImages: [Attachment(file: "fehlt.jpg"),
                                                                     Attachment(file: kept)])))
        let routed = RoutedSend(text: "zwei Bilder, dann ändern", plan: SendPlan.singleChat,
                                turn: ModelTurn(messages: [], images: []),
                                history: [], attachments: [], files: [], convID: UUID(), started: Date())
        let next = await routed.continuing(with: carry, since: 0, media: media)
        XCTAssertEqual(next.turn.pictureFiles, [kept], "ein fehlendes Bild verschiebt die Zuordnung nicht")
        XCTAssertEqual(next.turn.images.count, 1)
    }

    func testOnlyTheFreshStepsContinueTheChain() async throws {
        let media = scratchMediaStore()
        guard let first = media.storeImageData(FakePictureData.jpeg()),
              let second = media.storeImageData(FakePictureData.jpeg()),
              let third = media.storeImageData(FakePictureData.jpeg()) else { return XCTFail("kein Bild") }
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "eins", artifacts: AnswerArtifacts(outImages: [Attachment(file: first)])))
        let gallery = PictureGallery(query: "Bilder", pictures: [
            WebPicture(file: second, pageURL: "https://q.test/2", fullURL: "https://q.test/2.jpg",
                       title: "Zwei", domain: "q.test"),
            WebPicture(file: third, pageURL: "https://q.test/3", fullURL: "https://q.test/3.jpg",
                       title: "Drei", domain: "q.test"),
        ])
        carry.add(AnswerPiece(text: "zwei", artifacts: AnswerArtifacts(gallery: gallery)))
        let routed = RoutedSend(text: "frage", plan: SendPlan.singleChat,
                                turn: ModelTurn(messages: [], images: []), history: [], attachments: [], files: [],
                                convID: UUID(), started: Date())
        let next = await routed.continuing(with: carry, since: 1, media: media)
        XCTAssertEqual(next.history.map(\.text), ["zwei"], "nur die frische Stufe steht im Verlauf")
        XCTAssertEqual(next.turn.pictureFiles, [second, third], "die ganze frische Galerie reist mit")
        XCTAssertEqual(next.freshPictureFiles, [second, third])
        XCTAssertEqual(next.turn.images.count, 2)
        XCTAssertEqual(next.turn.messages.last?.role, .assistant)
    }

    func testASliceWithoutFreshContentKeepsTheStepAndItsFreshPictures() async throws {
        let media = scratchMediaStore()
        let routed = RoutedSend(text: "frage", plan: SendPlan.singleChat,
                                turn: ModelTurn(messages: [], images: []), history: [], attachments: [], files: [],
                                convID: UUID(), started: Date(), freshPictureFiles: ["alt.jpg"])
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "alt"))
        let next = await routed.continuing(with: carry, since: 1, media: media)
        XCTAssertEqual(next.freshPictureFiles, ["alt.jpg"])
        XCTAssertEqual(next.text, routed.text)
        XCTAssertTrue(next.history.isEmpty)
    }

    func testAnImageAlreadyInTheTurnIsNotAttachedAgain() async throws {
        let media = scratchMediaStore()
        guard let kept = media.storeImageData(FakePictureData.jpeg()) else { return XCTFail("kein Bild") }
        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "", artifacts: AnswerArtifacts(outImages: [Attachment(file: kept)])))
        let routed = RoutedSend(text: "und jetzt weiter", plan: SendPlan.singleChat,
                                turn: ModelTurn(messages: [], images: [Data([1, 2])], pictureFiles: [kept]),
                                history: [], attachments: [], files: [], convID: UUID(), started: Date())
        let next = await routed.continuing(with: carry, since: 0, media: media)
        XCTAssertEqual(next.turn.pictureFiles, [kept])
        XCTAssertEqual(next.turn.images.count, 1)
    }
}

@MainActor
final class ChainRunTests: GwenTestCase {
    func testStopLetsTheRunningStepFinishAndHoldsBackTheRest() {
        let run = ChainRun()
        run.requestStop()
        XCTAssertFalse(run.stopRequested, "ohne laufende Kette gibt es nichts anzuhalten")
        run.begin()
        XCTAssertTrue(run.isRunning)
        XCTAssertTrue(run.mayRun(step: 1))
        XCTAssertTrue(run.mayRun(step: 2))
        run.requestStop()
        XCTAssertTrue(run.mayRun(step: 1), "der erste Schritt läuft immer")
        XCTAssertFalse(run.mayRun(step: 2))
        run.end()
        XCTAssertFalse(run.isRunning)
        XCTAssertFalse(run.stopRequested)
        run.begin()
        XCTAssertTrue(run.mayRun(step: 5), "ein früherer Halt gilt nicht für die nächste Nachricht")
    }

    func testTheStopNoticeNamesHowManyStepsWereLeftOut() {
        XCTAssertTrue(L.fmt("chain_stopped", "4").hasSuffix("4"), L.fmt("chain_stopped", "4"))
    }
}
