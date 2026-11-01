@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class ChatThreadRowsViewTests: XCTestCase {
    private let media = MediaStore(paths: StoragePaths(documents: FileManager.default.temporaryDirectory))
    private let documents = DocumentStore(paths: StoragePaths(documents: FileManager.default.temporaryDirectory))
    private let photos = PhotoLibraryWriter()

    private func actions(marker: @escaping () -> Void = {}) -> ChatThreadRowActions {
        ChatThreadRowActions(onEdit: { _ in marker() },
                             onPreview: { _, _ in marker() },
                             onDelete: { _ in marker() }, onRoute: { _ in marker() })
    }

    private func rows(_ messages: [ChatMessage], settled: Bool = true,
                      actions: ChatThreadRowActions? = nil) -> ChatThreadRowsView {
        ChatThreadRowsView(messages: messages, lastIsSettled: settled, media: media,
                           documents: documents, photos: photos, actions: actions ?? self.actions())
    }

    func testFreshCallbacksAloneDoNotMakeTheRowsLookChanged() {
        let messages = [ChatMessage(role: .user, text: "Frage"), ChatMessage(role: .assistant, text: "Antwort")]
        var touched = 0
        let first = rows(messages, actions: actions { touched += 1 })
        let second = rows(messages, actions: actions { touched += 10 })
        XCTAssertEqual(first, second, "Tastendruck, Fokus oder Overlay dürfen die Zeilen nicht neu deklarieren")
        XCTAssertEqual(touched, 0)
    }

    func testANewMessageOrAChangedTextMakesTheRowsDiffer() {
        let base = [ChatMessage(id: UUID(), role: .user, text: "Frage")]
        let edited = [ChatMessage(id: base[0].id, role: .user, text: "Frage!")]
        XCTAssertNotEqual(rows(base), rows(base + [ChatMessage(role: .assistant, text: "Antwort")]))
        XCTAssertNotEqual(rows(base), rows(edited))
    }

    func testTheSettledFlagBelongsToTheRowsIdentity() {
        let messages = [ChatMessage(role: .assistant, text: "Antwort")]
        XCTAssertNotEqual(rows(messages, settled: true), rows(messages, settled: false),
                          "Die Uhrzeit unter der letzten Antwort erscheint erst nach dem Streaming")
    }

    func testAnotherMediaStoreMakesTheRowsDiffer() {
        let messages = [ChatMessage(role: .user, text: "Frage")]
        let other = MediaStore(paths: StoragePaths(documents: FileManager.default.temporaryDirectory
            .appendingPathComponent("anders")))
        XCTAssertNotEqual(rows(messages),
                          ChatThreadRowsView(messages: messages, lastIsSettled: true, media: other,
                                             documents: documents, photos: photos, actions: actions()))
    }

    func testAPendingReviewBelongsToTheRowsIdentity() {
        let message = ChatMessage(role: .assistant, text: "Antwort [1].")
        let plain = ChatThreadRowsView(messages: [message], lastIsSettled: true, media: media,
                                       documents: documents, photos: photos, actions: actions())
        let checking = ChatThreadRowsView(messages: [message], lastIsSettled: true,
                                          reviewing: [message.id], media: media,
                                          documents: documents, photos: photos, actions: actions())
        XCTAssertNotEqual(plain, checking, "der laufende Prüfstatus muss die Zeilen neu zeichnen")
    }
}
