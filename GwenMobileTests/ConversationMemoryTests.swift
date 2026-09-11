import XCTest
@testable import GwenMobile

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

    func testOnlyTheNewestAttachedPictureIsRemembered() {
        let history = [user("Was ist das?", images: ["alt.jpg"]), answer("Ein Hund."),
                       user("Und das hier?", images: ["neu.jpg"]), answer("Eine Katze."),
                       user("Welche Rasse?")]
        let turn = modelTurn(of: history, stored: "alt.jpg", "neu.jpg")
        XCTAssertEqual(turn.messages.filter { !$0.images.isEmpty }.map(\.text), ["Und das hier?"])
        XCTAssertEqual(turn.images.count, 1)
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

    func testAnEditResultReplacesTheOriginalPhotoInTheMemory() {
        let history = [user("Original", images: ["foto.jpg"]), answer("Bearbeiten.", generated: ["edit.jpg"]),
                       user("Mach noch mehr Kontrast")]
        let turn = modelTurn(of: history, stored: "foto.jpg", "edit.jpg")
        XCTAssertEqual(turn.messages.last?.images.map(\.file), ["edit.jpg"])
        XCTAssertEqual(turn.messages.first?.images, [])
    }

    func testAnAttachedPictureWinsOverAnEarlierGeneratedOne() {
        let history = [user("Male einen Turm"), answer("Turm.", generated: ["gen.jpg"]),
                       user("Und daneben ein Boot?", images: ["eigen.jpg"])]
        let turn = modelTurn(of: history, stored: "gen.jpg", "eigen.jpg")
        XCTAssertEqual(turn.messages.last?.images.map(\.file), ["eigen.jpg"])
        XCTAssertEqual(turn.images.count, 1)
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
        XCTAssertEqual(halfGone.messages.first?.images.map(\.file), ["da.jpg"])
        XCTAssertEqual(halfGone.images.count, 1)
        XCTAssertEqual(halfGone.messages.flatMap(\.images).count, halfGone.images.count)
    }

    func testRememberedImagesNameThePictureAFollowUpEditNeeds() {
        let history = [user("Male einen Turm"), answer("Turm.", generated: ["gen.jpg"]), user("Noch dunkler")]
        XCTAssertEqual(ConversationMemory.rememberedImages(from: history).map(\.file), ["gen.jpg"])
        let attached = [user("Original", images: ["foto.jpg"]), user("Und hier?")]
        XCTAssertEqual(ConversationMemory.rememberedImages(from: attached).map(\.file), ["foto.jpg"])
        XCTAssertTrue(ConversationMemory.rememberedImages(from: []).isEmpty)
    }

    func testAConversationWithoutAQuestionKeepsNoPictures() {
        let history = [answer("Nur eine Antwort.", generated: ["gen.jpg"])]
        let turn = modelTurn(of: history, stored: "gen.jpg")
        XCTAssertFalse(turn.needsVision)
        XCTAssertEqual(turn.messages.first?.images, [])
    }

    func testChartAnswerIsRememberedByItsTextAndItsPicture() {
        let history = [user("Such nach den Einwohnerzahlen und stell sie als Diagramm dar"),
                       answer("**Einwohner**\n\n- 2020: 83,2 Mio.", generated: ["chart.jpg"]),
                       user("Mach ein Liniendiagramm daraus")]
        let turn = modelTurn(of: history, stored: "chart.jpg")
        XCTAssertTrue(turn.messages[1].text.contains("83,2 Mio."))
        XCTAssertEqual(turn.messages.last?.images.map(\.file), ["chart.jpg"])
        XCTAssertEqual(turn.images.count, 1)
    }
}
