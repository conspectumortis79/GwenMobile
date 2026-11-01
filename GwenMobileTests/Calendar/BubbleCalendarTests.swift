@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import SwiftUI
import GwenMobileKit

@MainActor
final class BubbleCalendarTests: GwenTestCase {
    private lazy var paths = StoragePaths(documents: tempDocuments())
    private lazy var media = MediaStore(paths: paths)
    private lazy var documents = DocumentStore(paths: paths)
    private let photos = PhotoLibraryWriter()
    private let start = CalendarRefTests.noontime

    private func ref(_ id: String = "ID-1", title: String = "Zahnarzt") -> CalendarRef {
        CalendarRef(eventID: id, title: title, start: start)
    }

    private func message(_ text: String, calendar: CalendarRef?,
                        id: UUID = UUID(), date: Date = Date()) -> ChatMessage {
        ChatMessage(id: id, role: .assistant, text: text, date: date, calendarRef: calendar)
    }

    private func bubble(_ text: String, calendar: CalendarRef?) -> Bubble {
        Bubble(message: message(text, calendar: calendar), media: media, documents: documents,
               photos: photos)
    }

    private func height(of bubble: Bubble) -> CGFloat {
        let host = UIHostingController(rootView: AnyView(bubble))
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 1600)
        return host.sizeThatFits(in: CGSize(width: 360,
                                           height: UIView.layoutFittingExpandedSize.height)).height
    }

    func testTheAppointmentChipAddsABlockUnderTheAnswer() {
        let plain = height(of: bubble("✔ Termin angelegt: Zahnarzt", calendar: nil))
        let withChip = height(of: bubble("✔ Termin angelegt: Zahnarzt", calendar: ref()))
        XCTAssertGreaterThan(withChip - plain, 30,
                             "unter der Blase muss Abschnittszeile und Kapsel Platz finden")
    }

    func testTheSameAnswerWithoutARefKeepsItsOldShape() {
        let first = height(of: bubble("Normale Antwort", calendar: nil))
        let second = height(of: bubble("Normale Antwort", calendar: nil))
        XCTAssertEqual(first, second, accuracy: 0.5)
    }

    func testTheRefBelongsToTheBubblesIdentity() {
        let mark = UUID()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let first = Bubble(message: message("Antwort", calendar: ref(), id: mark, date: stamp),
                          media: media, documents: documents, photos: photos)
        let second = Bubble(message: message("Antwort", calendar: ref(), id: mark, date: stamp),
                           media: media, documents: documents, photos: photos)
        let without = Bubble(message: message("Antwort", calendar: nil, id: mark, date: stamp),
                            media: media, documents: documents, photos: photos)
        let other = Bubble(message: message("Antwort", calendar: ref("ID-2"), id: mark, date: stamp),
                          media: media, documents: documents, photos: photos)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, without,
                          "ein nachträglich gesetzter Chip darf nicht in der Zelle von vorher versickern")
        XCTAssertNotEqual(first, other)
    }

    func testTheChipCarriesItsTitleAndTimeIntoTheLayout() {
        let early = bubble("Antwort", calendar: ref(title: "Frühstück"))
        let late = bubble("Antwort", calendar: ref(title: "Zahnarzt sehr langer Titel der abgeschnitten wird"))
        XCTAssertEqual(height(of: early), height(of: late), accuracy: 1.5,
                       "lange Titel dürfen die Blase nicht in die Breite ziehen")
    }

    func testRowsDifferOnlyByTheirAppointmentRef() {
        let actions = ChatThreadRowActions(onEdit: { _ in }, onPreview: { _, _ in },
                                           onDelete: { _ in }, onRoute: { _ in })
        let mark = UUID()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let without = message("Antwort", calendar: nil, id: mark, date: stamp)
        let withChip = message("Antwort", calendar: ref(), id: mark, date: stamp)
        let plain = ChatThreadRowsView(messages: [without], lastIsSettled: true,
                                      media: media, documents: documents, photos: photos, actions: actions)
        let chip = ChatThreadRowsView(messages: [withChip],
                                     lastIsSettled: true, media: media, documents: documents,
                                     photos: photos, actions: actions)
        XCTAssertNotEqual(plain, chip,
                          "die Referenz auf den Termin ist der einzige Unterschied und muss die Zeile neu zeichnen lassen")
        XCTAssertEqual(plain, ChatThreadRowsView(messages: [without], lastIsSettled: true,
                                                media: media, documents: documents, photos: photos,
                                                actions: actions))
    }

    func testAnOpenCallbackIsOptionalJustLikeTheRouteOne() {
        let actions = ChatThreadRowActions(onEdit: { _ in }, onPreview: { _, _ in },
                                          onDelete: { _ in }, onRoute: { _ in })
        XCTAssertNil(actions.onOpenEvent)
        var opened: CalendarRef?
        var withCallback = actions
        withCallback.onOpenEvent = { opened = $0 }
        withCallback.onOpenEvent?(ref("ID-9"))
        XCTAssertEqual(opened, ref("ID-9"))
    }

    func testTheStoreWritesTheRefIntoTheHistoryAndReadsItBack() async throws {
        let store = ChatStore(media: media, paths: paths)
        let conversation = try XCTUnwrap(store.current?.id)
        store.appendAssistant("✔ Termin angelegt: Zahnarzt", model: "test", elapsed: 1.2,
                             to: conversation, calendar: ref("ID-7"))
        store.appendAssistant("✔ Termin gelöscht: Zahnarzt", model: "test", elapsed: 0.8,
                             to: conversation)
        try await settle(700)

        let reloaded = try XCTUnwrap(ConversationFolderPersistence(
            folder: paths.conversationsFolder,
            legacy: ConversationFilePersistence(url: paths.conversations)).load().conversations)
        XCTAssertEqual(reloaded.first?.messages.count, 2)
        let answers = try XCTUnwrap(reloaded.first?.messages.filter { $0.role == .assistant })
        XCTAssertEqual(answers.first?.calendarRef, ref("ID-7"))
        XCTAssertNil(answers.last?.calendarRef, "ein gelöschter Termin darf keinen Chip hinterlassen")
    }
}
