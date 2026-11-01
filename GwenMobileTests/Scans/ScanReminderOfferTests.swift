@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class ScanReminderOfferTests: GwenTestCase {
    private func plannedReminder(_ arguments: String) throws -> ReminderRequest {
        let decision = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool, arguments: arguments))
        guard case .reminder(let request) = decision.route else {
            throw NSError(domain: "ScanReminderOfferTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "kein Erinnerungsplan aus \(arguments)"])
        }
        return request
    }

    func testTheOfferComesFromThePlannedReminder() throws {
        let request = try plannedReminder(
            #"{"action":"create","title":"Stadtwerke-Rechnung bezahlen","due":"2026-10-15 09:00","list":"Erinnerungen"}"#)
        let offer = try XCTUnwrap(ScanReminderOffer(from: request))
        XCTAssertEqual(offer.title, "Stadtwerke-Rechnung bezahlen")
        XCTAssertEqual(offer.list, "Erinnerungen")
        XCTAssertNotNil(offer.due)
        XCTAssertTrue(offer.isUsable)
        let rebuilt = try XCTUnwrap(offer.request)
        XCTAssertEqual(rebuilt.action, .create)
        XCTAssertEqual(rebuilt.title, offer.title)
        XCTAssertEqual(rebuilt.list, offer.list)
        XCTAssertEqual(rebuilt.due, offer.due)
        XCTAssertFalse(rebuilt.allDay)
        XCTAssertNotNil(offer.chipStamp)
    }

    func testAnOfferWithoutADueDateIsRefused() throws {
        let request = try plannedReminder(#"{"action":"create","title":"Ohne Datum"}"#)
        XCTAssertNil(ScanReminderOffer(from: request))
        let empty = ScanReminderOffer(title: "   ", due: Date())
        XCTAssertFalse(empty.isUsable)
        XCTAssertNil(empty.request)
    }

    func testADayOnlyDeadlineStaysAnAllDayReminder() throws {
        let request = try plannedReminder(#"{"action":"create","title":"Frist prüfen","due":"2026-10-15"}"#)
        let offer = try XCTUnwrap(ScanReminderOffer(from: request))
        XCTAssertTrue(offer.allDay)
        XCTAssertTrue(try XCTUnwrap(offer.request).allDay)
    }

    func testTheStoreShowsTheOfferUntilTheUserTapsIt() throws {
        let paths = StoragePaths(documents: tempDocuments())
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        let convID = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Frist als Erinnerung scannen"), to: convID)
        let messageID = try XCTUnwrap(store.current?.messages.last?.id)
        let due = Date(timeIntervalSince1970: 1_792_000_000)
        let offer = ScanReminderOffer(title: "Stadtwerke bezahlen", due: due)
        store.attachReminderOffer(offer, to: messageID, in: convID)
        XCTAssertEqual(store.current?.messages.last?.reminderOffer, offer)
        XCTAssertNil(store.current?.messages.last?.reminderRef)
        let ref = ReminderRef(reminderID: "X1", title: offer.title, list: "Erinnerungen",
                              due: due, allDay: false, place: nil)
        store.settleReminderOffer(ref, to: messageID, in: convID)
        XCTAssertNil(store.current?.messages.last?.reminderOffer)
        XCTAssertEqual(store.current?.messages.last?.reminderRef, ref)
    }

    func testTheOfferSurvivesAStoredMessageRoundTrip() throws {
        let due = Date(timeIntervalSince1970: 1_792_000_000)
        let offer = ScanReminderOffer(title: "Frist prüfen", due: due, allDay: true,
                                      list: "Erinnerungen", notes: "Widerspruch")
        let message = ChatMessage(role: .assistant, text: "Text", reminderOffer: offer)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded.reminderOffer, offer)
        XCTAssertEqual(decoded.reminderOffer?.chipStamp, Formatters.day(due))
    }

    func testTheScanFileIsAttachedToTheAnswerForSharing() throws {
        let paths = StoragePaths(documents: tempDocuments())
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        let convID = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .assistant, text: "Zusammenfassung"), to: convID)
        let messageID = try XCTUnwrap(store.current?.messages.last?.id)
        let file = AttachedFile(file: "doc_x.pdf", name: "Kassenbon.pdf", kind: .pdf, bytes: 10,
                                pages: 1, chars: 5, via: .ocr)
        store.attachScanRef(file, to: messageID, in: convID)
        XCTAssertEqual(store.current?.messages.last?.scanRef, file)
        XCTAssertTrue(store.current?.messages.last?.documentFiles.contains(file.file) == true)
        let message = try XCTUnwrap(store.current?.messages.last)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded.scanRef, file)
    }
}
