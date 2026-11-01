@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ConversationMemoryTests: XCTestCase {
    private func loader(_ files: [String]) -> (Attachment) -> Data? {
        let stored = Set(files)
        return { stored.contains($0.file) ? Data([0xFF, 0xD8, 0xFF, 0xD9]) : nil }
    }

    private func user(_ text: String, images: [String] = []) -> ChatMessage {
        ChatMessage(role: .user, text: text, images: images.map { Attachment(file: $0) })
    }

    private func answer(_ text: String, generated: [String] = []) -> ChatMessage {
        ChatMessage(role: .assistant, text: text, outImages: generated.isEmpty ? nil : generated.map { Attachment(file: $0) })
    }

    private func modelTurn(of messages: [ChatMessage], stored files: String...) -> ModelTurn {
        ConversationMemory.turn(from: messages, load: loader(files))
    }

    func testPlainConversationTravelsAsTextOnly() {
        let history = [user("Was ist die Hauptstadt von Frankreich?"), answer("Paris."),
                       user("Und welche Sprache wird dort gesprochen?")]
        let turn = modelTurn(of: history)
        XCTAssertFalse(turn.needsVision)
        XCTAssertEqual(turn.messages.map(\.text),
                       ["Was ist die Hauptstadt von Frankreich?", "Paris.", "Und welche Sprache wird dort gesprochen?"])
    }

    func testEveryAttachedPictureOfTheChatTravelsInConversationOrder() {
        let history = [user("Was ist das?", images: ["alt.jpg"]), answer("Ein Hund."),
                       user("Und das hier?", images: ["neu.jpg"]), answer("Eine Katze."),
                       user("Welche Rasse?")]
        let turn = modelTurn(of: history, stored: "alt.jpg", "neu.jpg")
        XCTAssertEqual(turn.messages.last?.images.map(\.file), ["alt.jpg", "neu.jpg"])
        XCTAssertEqual(turn.images.count, 2)
        XCTAssertTrue(turn.needsVision)
    }

    func testAGeneratedPictureIsHandedToTheNextQuestion() {
        let history = [user("Male einen Leuchtturm"), answer("Hier ist dein Leuchtturm.", generated: ["gen.jpg"]),
                       user("Warum ist das Meer so grau?")]
        let turn = modelTurn(of: history, stored: "gen.jpg")
        XCTAssertEqual(turn.messages.last?.images, [Attachment(file: "gen.jpg")])
        XCTAssertEqual(turn.images.count, 1)
        XCTAssertTrue(turn.needsVision)
        XCTAssertFalse(turn.messages[1].outImages?.isEmpty ?? true)
    }

    func testAnEditResultKeepsItsOriginalInTheMemory() {
        let history = [user("Original", images: ["foto.jpg"]), answer("Bearbeiten.", generated: ["edit.jpg"]),
                       user("Mach noch mehr Kontrast")]
        let turn = modelTurn(of: history, stored: "foto.jpg", "edit.jpg")
        XCTAssertEqual(turn.messages.last?.images.map(\.file), ["foto.jpg", "edit.jpg"])
        XCTAssertEqual(turn.messages.filter { $0.text == "Original" }.first?.images, [])
    }

    func testAttachedAndGeneratedPicturesArriveNewestLast() {
        let history = [user("Male einen Turm"), answer("Turm.", generated: ["gen.jpg"]),
                       user("Und daneben ein Boot?", images: ["eigen.jpg"])]
        let turn = modelTurn(of: history, stored: "gen.jpg", "eigen.jpg")
        XCTAssertEqual(turn.messages.last?.images.map(\.file), ["gen.jpg", "eigen.jpg"])
        XCTAssertEqual(turn.images.count, 2)
    }

    func testTheWindowStopsAtTheNewestTurns() {
        let history = (0..<(ConversationMemory.maxMessages + 12)).map { index in
            index.isMultiple(of: 2) ? user("Frage \(index)") : answer("Antwort \(index)")
        }
        let turn = modelTurn(of: history)
        XCTAssertEqual(turn.messages.count, ConversationMemory.maxMessages)
        XCTAssertEqual(turn.messages.last?.text, history.last?.text)
        XCTAssertEqual(turn.messages.first?.text, "Frage 12")
    }

    func testUnreadableFilesAreDroppedFromMessageAndBytesTogether() {
        let history = [user("Was ist das?", images: ["kaputt.jpg"]), answer("Ein Keks."),
                       user("Und jetzt?")]
        let broken = modelTurn(of: history, stored: "anderes.jpg")
        XCTAssertFalse(broken.needsVision)
        XCTAssertEqual(broken.messages.flatMap(\.images).count, broken.images.count)

        let halfGone = modelTurn(of: [user("Zwei Bilder", images: ["da.jpg", "fort.jpg"]), user("Nochmal?")],
                            stored: "da.jpg")
        XCTAssertEqual(halfGone.messages.last?.images.map(\.file), ["da.jpg"])
        XCTAssertEqual(halfGone.messages.first?.images, [])
        XCTAssertEqual(halfGone.images.count, 1)
        XCTAssertEqual(halfGone.messages.flatMap(\.images).count, halfGone.images.count)
    }

    func testRememberedPicturesNameThePictureAFollowUpEditNeeds() {
        let history = [user("Male einen Turm"), answer("Turm.", generated: ["gen.jpg"]), user("Noch dunkler")]
        XCTAssertEqual(modelTurn(of: history, stored: "gen.jpg").pictureFiles, ["gen.jpg"])
        let attached = [user("Original", images: ["foto.jpg"]), user("Und hier?")]
        XCTAssertEqual(modelTurn(of: attached, stored: "foto.jpg").pictureFiles, ["foto.jpg"])
        XCTAssertTrue(modelTurn(of: []).pictureFiles.isEmpty)
    }

    func testAnAttachedVideoTravelsAsVideoDataAndIsNotInlinedAsText() {
        let video = AttachedFile(file: "doc_v.mp4", name: "clip.mp4", kind: .video, bytes: 12)
        let message = ChatMessage(role: .user, text: "Was passiert hier?", files: [video])
        let bytes = Data([0, 0, 0, 0x18]) + Data("ftypisom".utf8)
        let turn = ConversationMemory.turn(from: [message], load: loader([]),
                                           fileText: { _ in "darf nicht als text kommen" },
                                           videoData: { $0 == "doc_v.mp4" ? bytes : nil })
        XCTAssertTrue(turn.needsVideo)
        XCTAssertEqual(turn.videoFiles, ["doc_v.mp4"])
        XCTAssertEqual(turn.videos, [bytes])
        XCTAssertEqual(turn.messages.first?.text, "Was passiert hier?")
        XCTAssertFalse(turn.withoutPictures().needsVideo)
    }

    func testOnlyTheNewestReadableVideoOfTheQuestionTravels() {
        let first = AttachedFile(file: "doc_old.mp4", name: "alt.mp4", kind: .video, bytes: 12)
        let second = AttachedFile(file: "doc_new.mp4", name: "neu.mp4", kind: .video, bytes: 12)
        let broken = AttachedFile(file: "doc_broken.mp4", name: "kaputt.mp4", kind: .video, bytes: 12)
        let message = ChatMessage(role: .user, text: "Vergleiche", files: [first, broken, second])
        let turn = ConversationMemory.turn(from: [message], load: loader([]),
                                           videoData: { name in
            name == "doc_new.mp4" ? Data([0, 0, 0, 0x18]) : nil
        })
        XCTAssertEqual(turn.videoFiles, ["doc_new.mp4"])
        XCTAssertEqual(turn.videos.count, 1)
        let missing = ConversationMemory.turn(from: [message], load: loader([]),
                                               videoData: { _ in nil })
        XCTAssertFalse(missing.needsVideo)
        let oversized = ConversationMemory.turn(from: [message], load: loader([]),
                                                 videoData: { _ in
            Data(repeating: 0, count: VideoPolicy.maximumAttachmentBytes + 1)
        })
        XCTAssertFalse(oversized.needsVideo)
        let followUp = ChatMessage(role: .user, text: "Und am Ende?")
        let carried = ConversationMemory.turn(from: [message,
                                                     ChatMessage(role: .assistant, text: "Ein Clip."),
                                                     followUp],
                                              load: loader([]),
                                              videoData: { $0 == "doc_new.mp4" ? Data([1, 2, 3]) : nil })
        XCTAssertEqual(carried.videoFiles, ["doc_new.mp4"])
    }

    func testAConversationWithoutAQuestionKeepsNoPictures() {
        let history = [answer("Nur eine Antwort.", generated: ["gen.jpg"])]
        let turn = modelTurn(of: history, stored: "gen.jpg")
        XCTAssertFalse(turn.needsVision)
        XCTAssertEqual(turn.messages.first?.images, [])
    }

    func testAnAnswerWithAPictureIsRememberedByItsTextAndItsPicture() {
        let history = [user("Zeig mir einen Berg bei Sonnenuntergang"),
                       answer("**Berg**\n\nHier ist das Bild.", generated: ["berg.jpg"]),
                       user("Mach es schwarzweiß")]
        let turn = modelTurn(of: history, stored: "berg.jpg")
        XCTAssertTrue(turn.messages[1].text.contains("Hier ist das Bild."))
        XCTAssertEqual(turn.messages.last?.images.map(\.file), ["berg.jpg"])
        XCTAssertEqual(turn.images.count, 1)
    }

    func testAPictureSentAgainStaysAtItsFirstPlaceInTheMemory() {
        let history = [user("Erstes", images: ["a.jpg"]), user("Zweites", images: ["b.jpg"]),
                       user("Nochmal", images: ["a.jpg"])]
        let turn = modelTurn(of: history, stored: "a.jpg", "b.jpg")
        XCTAssertEqual(turn.messages.last?.images.map(\.file), ["a.jpg", "b.jpg"])
        XCTAssertEqual(turn.images.count, 2)
    }

    func testPositionsNameTheSlotEachFreshPictureFills() {
        let history = [user("Erstes", images: ["a.jpg"]), user("Zweites", images: ["b.jpg"]),
                       user("Nochmal", images: ["b.jpg"])]
        let turn = modelTurn(of: history, stored: "a.jpg", "b.jpg")
        XCTAssertEqual(turn.pictureFiles, ["a.jpg", "b.jpg"])
        XCTAssertEqual(turn.positions(of: ["b.jpg"]), [2])
        XCTAssertEqual(turn.positions(of: ["fehit.jpg"]), [])
        XCTAssertEqual(turn.withoutPictures().pictureCount, 0)
        XCTAssertEqual(turn.pictureCount, 2)
    }

    func testEveryPictureOfTheChatTravelsWithTheRequest() {
        let history = [user("Was ist das?", images: ["a.jpg"]), answer("Ein Hund."),
                       user("Und das hier?", images: ["b.jpg"]), answer("Eine Katze."),
                       user("Übertrage die Farbe aus dem zweiten Foto auf das erste Foto")]
        let turn = ConversationMemory.turn(from: history, load: loader(["a.jpg", "b.jpg"]))
        XCTAssertEqual(turn.messages.last?.images.map(\.file), ["a.jpg", "b.jpg"])
        XCTAssertEqual(turn.pictureCount, 2)
        XCTAssertTrue(turn.needsVision)
    }

    func testGeneratedPicturesAreRememberedTheSameWayAsAttachedOnes() {
        let history = [user("Male einen Turm"), answer("Turm.", generated: ["gen1.jpg"]),
                       user("Male ein Boot"), answer("Boot.", generated: ["gen2.jpg"]),
                       user("Vergleiche das erste bild mit dem zweiten")]
        let turn = ConversationMemory.turn(from: history, load: loader(["gen1.jpg", "gen2.jpg"]))
        XCTAssertEqual(turn.messages.last?.images.map(\.file), ["gen1.jpg", "gen2.jpg"])
    }

    func testThePictureSelectionKeepsTheFirstChatPictureAndTheNewestOnes() {
        let stored = (1...(ConversationMemory.maxPictures + 2)).map { "p\($0).jpg" }
        var history: [ChatMessage] = []
        for (index, file) in stored.enumerated() {
            history.append(user("Foto \(index + 1)", images: [file]))
            history.append(answer("Notiz \(index + 1)"))
        }
        history.append(user("Nimm die farben vom ersten bild für das letzte"))
        let turn = ConversationMemory.turn(from: history, load: loader(stored))
        XCTAssertEqual(turn.messages.last?.images.map(\.file),
                       [stored.first!] + Array(stored.suffix(ConversationMemory.maxPictures - 1)))
        XCTAssertEqual(turn.pictureCount, ConversationMemory.maxPictures)
        XCTAssertEqual(turn.chatPictureCount, stored.count)
        XCTAssertEqual(turn.picturesLeftBehind, stored.count - ConversationMemory.maxPictures)
        XCTAssertEqual(turn.messages.flatMap(\.images).count, turn.images.count)
    }

    func testTheTurnKnowsWhichChatPicturesAreReachable() {
        let stored = (1...(ConversationMemory.maxPictures + 1)).map { "p\($0).jpg" }
        var history: [ChatMessage] = []
        for file in stored { history.append(user("Foto", images: [file])) }
        let turn = ConversationMemory.turn(from: history, load: loader(stored))
        XCTAssertEqual(turn.pictureCount, ConversationMemory.maxPictures)
        XCTAssertEqual(turn.chatPictureCount, stored.count)
        XCTAssertEqual(turn.picturesLeftBehind, stored.count - ConversationMemory.maxPictures)
    }

    func testUnreadablePicturesAreDroppedFromTheWholeSelection() {
        let history = [user("Erstes", images: ["kaputt.jpg"]), user("Zweites", images: ["heil.jpg"]),
                       user("Vergleiche das erste foto mit dem zweiten foto")]
        let turn = ConversationMemory.turn(from: history, load: loader(["heil.jpg"]))
        XCTAssertEqual(turn.messages.last?.images.map(\.file), ["heil.jpg"])
        XCTAssertEqual(turn.images.count, 1)
    }

    func testRememberedPicturesListEveryPictureWithTheNewestLast() {
        let history = [user("Erstes", images: ["a.jpg"]), user("Zweites", images: ["b.jpg"]), user("Noch eine Frage")]
        XCTAssertEqual(modelTurn(of: history, stored: "a.jpg", "b.jpg").pictureFiles, ["a.jpg", "b.jpg"])
    }

    func testABrokenFileDoesNotCostASlotOfTheBudget() {
        let stored = (1...(ConversationMemory.maxPictures + 2)).map { "p\($0).jpg" }
        var history: [ChatMessage] = []
        for file in stored { history.append(user("Foto", images: [file])) }
        history.append(user("Vergleiche die bilder miteinander"))
        let readable = Array(stored.dropFirst())
        let turn = ConversationMemory.turn(from: history, load: loader(readable))
        XCTAssertEqual(turn.messages.last?.images.map(\.file), Array(stored.suffix(ConversationMemory.maxPictures)))
        XCTAssertEqual(turn.pictureCount, ConversationMemory.maxPictures)
    }

    func testTheBudgetTopsUpFromTheNextUsablePicture() {
        let stored = (1...(ConversationMemory.maxPictures + 2)).map { "p\($0).jpg" }
        var history: [ChatMessage] = []
        for file in stored { history.append(user("Foto", images: [file])) }
        history.append(user("Vergleiche die bilder miteinander"))
        let readable = [stored.first!] + stored.dropLast()
        let turn = ConversationMemory.turn(from: history, load: loader(readable))
        XCTAssertEqual(turn.messages.last?.images.map(\.file),
                       ["p1.jpg"] + Array(stored[2..<(ConversationMemory.maxPictures + 1)]))
        XCTAssertEqual(turn.images.count, ConversationMemory.maxPictures)
    }
}
