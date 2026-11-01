@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class ChatStoreGapCoverageTests: GwenTestCase {
    private func makeStore(_ prefix: String) -> ChatStore {
        let paths = temporaryPaths(prefix)
        return ChatStore(media: MediaStore(paths: paths), paths: paths)
    }

    func testTheRestoreAndAttachmentHelpers() throws {
        let store = makeStore("store-gap")
        store.newConversation()
        let conv = try XCTUnwrap(store.current?.id)
        let msg = ChatMessage(role: .user, text: "Hallo")
        XCTAssertTrue(store.appendMessage(msg, to: conv))
        XCTAssertFalse(store.appendMessage(msg, to: UUID()))
        let assistant = store.appendAssistant("Antwort", model: "m", elapsed: 1, to: conv)
        XCTAssertNotNil(assistant)
        let missingAssistant = store.appendAssistant("Antwort", model: "m", elapsed: 1, to: UUID())
        XCTAssertNil(missingAssistant)
        store.replaceAssistant(UUID(), in: conv, with: ChatMessage(role: .assistant, text: "x"))
        let removed = store.removeMessage(msg.id, from: conv)
        XCTAssertNotNil(removed)
        if let removed {
            store.restoreMessage(removed.message, to: conv, at: removed.index)
        }
        store.restoreMessage(msg, to: UUID(), at: 0)
        store.restoreConversation(at: 0, Conversation(title: "Kopie"))
        let file = AttachedFile(file: "doc.pdf", name: "doc.pdf", kind: .pdf, bytes: 10)
        store.attachScan(file, to: msg.id, in: conv)
        store.attachScan(file, to: UUID(), in: conv)
        store.attachScanRef(file, to: msg.id, in: conv)
        XCTAssertNotNil(store.current?.messages.first(where: { $0.id == msg.id })?.scanRef)
        store.stand(in: PhotoLibraryWriter(library: FakePhotoLibrary()))
        store.restorePhotos()
        store.restorePhotos()
    }
}
