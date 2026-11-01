@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class ChatSmallGapsTests: GwenTestCase {
    private struct OddFailure: Error {}

    private func makeStore(_ prefix: String) -> ChatStore {
        let paths = temporaryPaths(prefix)
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        store.newConversation()
        return store
    }

    func testTheAnswerExporterWithoutAQuestion() throws {
        let exporter = AnswerExporter(paths: temporaryPaths("answer-gap"))
        let url = try exporter.write(text: "Antwort", sources: [], question: nil)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("Antwort"))
    }

    func testTheChatRequestMergesExtraFields() throws {
        let request = try ChatRequest.post(baseURL: "https://q.test/v1", key: "k", model: "m",
                                           messages: [], stream: false, thinking: .nothing,
                                           timeout: 30, extra: ["top_p": 0.5])
        XCTAssertEqual(jsonBody(of: request)?["top_p"] as? Double, 0.5)
    }

    func testTheAnswerErrorReadsForeignErrorsAndPolicyText() {
        let foreign = AnswerError.model(OddFailure(), model: nil, generic: L.t("err_generic"))
        XCTAssertTrue(foreign.hasPrefix(AnswerError.marker), foreign)
        let policy = AnswerError.model("The content policy was violated", model: nil,
                                       generic: L.t("err_generic"))
        XCTAssertTrue(policy.contains(L.t("err_content_policy")), policy)
    }

    func testACreatedAppointmentIsNotMatchedByALongerDifferentTitle() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let created = CalendarRef(eventID: "event", title: "Zahnarzt", start: start)
        let carry = AnswerCarry()
        carry.notePlanned("Termin angelegt", ref: created)
        var plan = QwenAPI.CalendarPlan(action: .create)
        plan.title = "Zahnarzt Kontrolle"
        plan.start = Formatters.eventDateTime(start)
        XCTAssertFalse(carry.createdAlready(plan))
        XCTAssertFalse(carry.createdAppointment(named: "Zahnarzt Kontrolle"))
        XCTAssertTrue(carry.createdAppointment(named: "Zahnarzt"))
    }

    func testTheChatRunnerWrapsForeignErrors() async {
        let runner = ChatRunner { _ in
            AsyncThrowingStream { continuation in
                continuation.yield("anfang")
                continuation.finish(throwing: OddFailure())
            }
        }
        do {
            _ = try await runner.run(URLRequest(url: URL(string: "https://x.test/odd")!), onChunk: { _ in })
            XCTFail("erwartet Fehler")
        } catch let error as APIError {
            XCTAssertEqual(error.recoveredText, "anfang")
            XCTAssertFalse(error.message.isEmpty)
        } catch {
            XCTFail("unerwarteter Fehler \(error)")
        }
        let early = ChatRunner { _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: OddFailure())
            }
        }
        do {
            _ = try await early.run(URLRequest(url: URL(string: "https://x.test/frueh")!), onChunk: { _ in })
            XCTFail("erwartet Fehler")
        } catch let error as APIError {
            XCTAssertNil(error.recoveredText)
        } catch {
            XCTFail("unerwarteter Fehler \(error)")
        }
    }

    func testTheChatRunnerCancelsTheRunningAnswer() async {
        let runner = ChatRunner { _ in
            AsyncThrowingStream { continuation in
                continuation.yield("teil")
            }
        }
        let task = Task {
            try await runner.run(URLRequest(url: URL(string: "https://x.test/lang")!), onChunk: { _ in })
        }
        try? await Task.sleep(for: .milliseconds(80))
        task.cancel()
        let outcome = await task.result
        switch outcome {
        case .success(let text):
            XCTAssertEqual(text, "teil")
        case .failure(let error):
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testTheAnswerCarryMergesMemoryRefsAndGuards() throws {
        var old = AnswerArtifacts()
        old.memoryRefs = [MemoryRef(entry: MemoryEntry(text: "mag Tee", category: .likes))]
        var fresh = AnswerArtifacts()
        fresh.memoryRefs = [MemoryRef(entry: MemoryEntry(text: "mag Tee", category: .likes)),
                            MemoryRef(entry: MemoryEntry(text: "arbeitet viel", category: .work))]
        let merged = old.merged(with: fresh)
        XCTAssertEqual(merged.memoryRefs?.map(\.text), ["mag Tee", "arbeitet viel"])

        let carry = AnswerCarry()
        XCTAssertFalse(carry.createdAppointment(named: "   "))
        carry.notePlanned("Zahnarzt", ref: CalendarRef(eventID: "e1", title: "Zahnarzt", start: Date()))
        XCTAssertTrue(carry.createdAppointment(named: "zahnarzt"))
        XCTAssertFalse(carry.setSourceReview(SourceReview(), forStep: 4))
        XCTAssertNil(carry.add(AnswerPiece(text: "  ")))
        XCTAssertNotNil(carry.add(AnswerPiece(text: "Antwort", step: 0)))
        XCTAssertTrue(carry.setSourceReview(SourceReview(), forStep: 0))
        let plan = try? JSONDecoder().decode(QwenAPI.CalendarPlan.self,
                                             from: Data(#"{"action":"create","title":"Zahnarzt"}"#.utf8))
        XCTAssertTrue(carry.createdAlready(try XCTUnwrap(plan)))
        let dated = try XCTUnwrap(JSONDecoder().decode(QwenAPI.CalendarPlan.self,
                                                       from: Data(#"{"action":"create","title":"Zahnarzt","start":"2026-10-05 09:00"}"#.utf8)))
        let start = try XCTUnwrap(dated.startDate)
        carry.notePlanned("Zahnarzt", ref: CalendarRef(eventID: "e2", title: "Zahnarzt", start: start))
        XCTAssertTrue(carry.createdAlready(dated))
    }

    func testAFlushIntoAMissingConversationCreatesNoMessage() {
        let store = makeStore("chain-flush-missing")
        let writer = ChainMessageWriter()
        writer.carry.add(AnswerPiece(text: "Antwort"))
        writer.flush(to: store, convID: UUID(), started: Date())
        XCTAssertNil(writer.messageID)
        XCTAssertTrue(store.current?.messages.isEmpty ?? true)
    }

    func testTheChainWriterAndPlacementGuards() {
        let store = makeStore("chain-gap")
        let convID = store.current?.id ?? UUID()
        let writer = ChainMessageWriter()
        writer.flush(to: store, convID: convID, started: Date())
        XCTAssertNil(writer.messageID)
        writer.carry.add(AnswerPiece(text: "Antwort"))
        writer.flush(to: store, convID: convID, started: Date())
        XCTAssertNotNil(writer.messageID)
        writer.flush(to: store, convID: convID, started: Date())
        let slot = AnswerSlot(writer: ChainMessageWriter(), writes: false)
        XCTAssertFalse(slot.store(AnswerPiece(text: "später"), to: store, convID: convID, started: Date()))
        XCTAssertEqual(slot.carry.pieces.count, 1)
        let writing = AnswerSlot(writer: ChainMessageWriter())
        XCTAssertTrue(writing.store(AnswerPiece(text: "jetzt"), to: store, convID: convID, started: Date()))
        let placement = AnswerPlacement(messageID: nil, slot: nil,
                                        convID: convID, started: Date())
        XCTAssertFalse(placement.applySourceReview(SourceReview(), to: store))
        let messageID = try? XCTUnwrap(store.current?.messages.last?.id)
        if let messageID {
            let found = AnswerPlacement(messageID: messageID, slot: nil,
                                        convID: convID, started: Date())
            XCTAssertTrue(found.applySourceReview(SourceReview(), to: store))
        }
    }

    func testTheChatMessageDecoderDropsBrokenRefs() throws {
        let json = """
        {"role":"assistant","text":"x",
         "reminderRef":{"reminderID":"","title":"T","list":"L"},
         "reminderOffer":{"title":" ","due":null},
         "scanRef":{"file":"","name":"x","kind":"pdf","bytes":1},
         "weatherRef":{"place":"x","latitude":0,"longitude":0,"day":"","hours":[]},
         "priceWatchRef":{"product":"","goal":0},
         "dayBriefingRef":{"date":"","greetingKey":"k"},
         "gallery":{"pictures":[]},
         "memoryRefs":[{"text":"m","category":"person"}]}
        """
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        XCTAssertNil(message.reminderRef)
        XCTAssertNil(message.reminderOffer)
        XCTAssertNil(message.scanRef)
        XCTAssertNil(message.weatherRef)
        XCTAssertNil(message.priceWatchRef)
        XCTAssertNil(message.dayBriefingRef)
        XCTAssertNil(message.gallery)
        XCTAssertEqual(message.memoryRefs?.count, 1)
        XCTAssertFalse(message.hasGallery)
        XCTAssertTrue(message.allPlaces.isEmpty)
    }

    func testTheMemoryKeepsTheOldestAndSkipsItInTheNewestLoop() {
        let images = ["old.jpg"] + (0..<10).map { "x\($0).jpg" }
        let history = [ChatMessage(role: .user, text: "Was ist das?",
                                   images: images.map { Attachment(file: $0) })]
        let turn = ConversationMemory.turn(from: history) { picture in
            picture.file == "old.jpg" ? Data([0xFF, 0xD8]) : nil
        }
        XCTAssertEqual(turn.pictureFiles, ["old.jpg"])
        XCTAssertEqual(turn.images.count, 1)
    }

    func testAConversationWithoutAQuestionDropsTheImages() {
        let history = [ChatMessage(role: .assistant, text: "Antwort",
                                   images: [Attachment(file: "a.jpg")])]
        let turn = ConversationMemory.turn(from: history, load: { _ in Data([1]) })
        XCTAssertTrue(turn.images.isEmpty)
        XCTAssertTrue(turn.messages[0].images.isEmpty)
        let plain = [ChatMessage(role: .assistant, text: "Antwort")]
        let untouched = ConversationMemory.turn(from: plain, load: { _ in nil })
        XCTAssertTrue(untouched.messages[0].images.isEmpty)
    }

    func testTheMemoryReadsTheFileTextThroughTheDefaultClosure() {
        let file = AttachedFile(file: "doc.pdf", name: "doc.pdf", kind: .pdf, bytes: 120, chars: 500)
        let history = [ChatMessage(role: .user, text: "Frage", files: [file])]
        let turn = ConversationMemory.turn(from: history, load: { _ in nil })
        XCTAssertEqual(turn.messages.last?.text, "Frage")
    }

    func testTheGalleryAndPlacesSurviveTheMessageRoundTrip() throws {
        var message = ChatMessage(role: .assistant, text: "Antwort")
        message.gallery = PictureGallery(query: "q", pictures: [
            WebPicture(file: "a.jpg", pageURL: "https://a.test/p", fullURL: "https://a.test/f",
                       title: "A", domain: "a.test"),
        ])
        message.placeGroups = [PlaceGroup(headingKey: "place_head",
                                          places: [NearbyPlace(name: "Apotheke", metres: 300)])]
        let data = try JSONEncoder().encode(message)
        let back = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertTrue(back.hasGallery)
        XCTAssertEqual(back.allPlaces.map(\.name), ["Apotheke"])
    }

    func testTheStatusAndSourceViewsDrawTheirStates() {
        XCTAssertNotNil(renderView(BubbleStatusLine(notice: "Hinweis", isLast: true,
                                                    time: "12:00", isUser: true), width: 320))
        _ = BubbleStatusLine(notice: nil, isLast: false, time: nil, isUser: false)
        XCTAssertNotNil(renderView(SourceChipLabel(number: 1, domain: "a.test", flagged: true), width: 320))
        XCTAssertNotNil(renderView(SourceChipLabel(number: 2, domain: "b.test"), width: 320))
        var review = SourceReview()
        review.sourceGroups = [[]]
        XCTAssertNotNil(renderView(SourceNetworkView(review: review, sources: []), width: 320))
        XCTAssertNotNil(renderView(ProcessingDots(), width: 60))
    }

    @MainActor
    func testTheThreadMetricsDefaultsAndGuards() {
        let metrics = ChatThreadMetrics()
        XCTAssertEqual(metrics, ChatThreadMetrics(contentWidth: 0, scrollOffset: 0, viewportHeight: 0,
                                                 viewportWidth: 0, bottomInset: 0))
        let view = ThreadMetricsView(frame: .zero)
        view.publishNow()
        view.didMoveToWindow()
        view.layoutSubviews()
        XCTAssertNil(view.onMetrics)
    }
}
