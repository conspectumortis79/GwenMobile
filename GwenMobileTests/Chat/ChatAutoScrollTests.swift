@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import Combine
import GwenMobileKit

@MainActor
final class ScrollRecorder {
    private(set) var anchors: [AnyHashable] = []

    var action: ChatAutoScroll.ScrollAction {
        { [weak self] anchor in self?.append(anchor) }
    }

    var calls: Int { anchors.count }
    var lastAnchor: AnyHashable? { anchors.last }

    func reset() { anchors = [] }

    private func append(_ anchor: AnyHashable) { anchors.append(anchor) }
}

@MainActor
final class FakeTime {
    private(set) var date = Date(timeIntervalSince1970: 1_700_000_000)

    var reading: @MainActor () -> Date {
        { self.date }
    }

    func advance(_ seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }
}

@MainActor
final class ChatAutoScrollTests: XCTestCase {
    private let anchor = AnyHashable("msg-test")
    private let viewport: CGFloat = 520

    private func timedScroller(_ time: FakeTime) -> ChatAutoScroll {
        ChatAutoScroll(pins: BottomPinTracker(tolerance: 64, now: time.reading), now: time.reading)
    }

    func testMessageAnchorCarriesTheIdentityTheThreadRowsUse() {
        let id = UUID()
        let message = ChatMessage(id: id, role: .assistant, text: "hallo")
        XCTAssertEqual(ChatScrollAnchors.message(id), "msg-\(id.uuidString)")
        XCTAssertEqual(ChatScrollAnchors.bottom(lastMessageID: id, statusRows: []),
                       AnyHashable(ChatThreadRow.message(message).id))
        XCTAssertNil(ChatScrollAnchors.bottom(lastMessageID: nil, statusRows: []))
    }

    func testBottomAnchorAlwaysNamesTheNewestRowOfTheThread() {
        let rows = ChatThreadStatusRow.present(streaming: "textet", transcribing: "hört",
                                               processing: "erzeugt", researching: "sucht")
        XCTAssertEqual(rows.map(\.id), [ChatScrollAnchors.streaming, ChatScrollAnchors.asrWorking,
                                        ChatScrollAnchors.imageWorking, ChatScrollAnchors.webStatus])
        let id = UUID()
        XCTAssertEqual(ChatScrollAnchors.bottom(lastMessageID: id, statusRows: rows),
                       AnyHashable(ChatScrollAnchors.webStatus))
        XCTAssertEqual(ChatScrollAnchors.bottom(lastMessageID: id, statusRows: Array(rows.dropLast())),
                       AnyHashable(ChatScrollAnchors.imageWorking))
        XCTAssertEqual(ChatScrollAnchors.bottom(lastMessageID: id, statusRows: [rows[1]]),
                       AnyHashable(ChatScrollAnchors.asrWorking))
        XCTAssertEqual(ChatScrollAnchors.bottom(lastMessageID: id, statusRows: [rows[0]]),
                       AnyHashable(ChatScrollAnchors.streaming))
        XCTAssertEqual(ChatScrollAnchors.bottom(lastMessageID: id, statusRows: []),
                       AnyHashable("msg-\(id.uuidString)"))
    }

    func testSilentStatusRowsNeitherAppearInTheThreadNorBlockTheAnchor() {
        XCTAssertTrue(ChatThreadStatusRow.present(streaming: nil, transcribing: nil,
                                                  processing: nil, researching: nil).isEmpty)
    }

    func testGroupingInsertsADayLabelOnlyWhenTheDayActuallyChanges() {
        let noon = Date(timeIntervalSince1970: 1_700_000_000)
        let messages = [ChatMessage(id: UUID(), role: .user, text: "a", date: noon),
                        ChatMessage(id: UUID(), role: .assistant, text: "b", date: noon.addingTimeInterval(120)),
                        ChatMessage(id: UUID(), role: .user, text: "c", date: noon.addingTimeInterval(90_000))]
        let rows = ChatThreadRow.grouped(messages)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].id, "day-\(noon.timeIntervalSince1970)")
        XCTAssertEqual(rows[1].id, ChatScrollAnchors.message(messages[0].id))
        XCTAssertEqual(rows[2].id, ChatScrollAnchors.message(messages[1].id))
        XCTAssertEqual(rows[4].id, ChatScrollAnchors.message(messages[2].id))
    }

    func testDistanceToBottomIsReadFromTheThreadGeometry() {
        XCTAssertEqual(metrics(content: 1200, offset: 400).distanceToBottom, 280, accuracy: 0.01)
        XCTAssertEqual(metrics(content: 300, offset: 0).distanceToBottom, 0, accuracy: 0.01)
    }

    func testTheBottomInsetEnlargesTheWayToTheEndTheSameWayUIKitDoes() {
        let inset = ChatThreadMetrics(contentHeight: 1400, scrollOffset: 880, viewportHeight: 520,
                                     bottomInset: 200)
        XCTAssertEqual(inset.distanceToBottom, 200, accuracy: 0.01)
        let flat = ChatThreadMetrics(contentHeight: 1400, scrollOffset: 880, viewportHeight: 520)
        XCTAssertEqual(flat.distanceToBottom, 0, accuracy: 0.01)
    }

    func testGrowthBelowTheFoldKeepsThePinWhileAReaderScrollingUpReleasesIt() {
        let tracker = BottomPinTracker(tolerance: 64)
        XCTAssertTrue(tracker.record(metrics(content: 1400, offset: 880)).atBottom)
        let grown = tracker.record(metrics(content: 1600, offset: 880))
        XCTAssertTrue(grown.contentGrew)
        XCTAssertFalse(grown.userMovedAwayFromBottom)
        XCTAssertTrue(tracker.isPinnedToBottom, "Ein Bild, das nachlädt, löst die Nadel nicht")
        let upstairs = tracker.record(metrics(content: 1600, offset: 400))
        XCTAssertTrue(upstairs.userMovedAwayFromBottom)
        XCTAssertFalse(tracker.isPinnedToBottom)
    }

    func testThePinReturnsAsSoonAsTheReaderReachesTheBottomAgain() {
        let tracker = BottomPinTracker(tolerance: 64)
        tracker.record(metrics(content: 1400, offset: 880))
        tracker.record(metrics(content: 1400, offset: 400))
        XCTAssertFalse(tracker.isPinnedToBottom)
        XCTAssertTrue(tracker.record(metrics(content: 1400, offset: 880)).atBottom)
        XCTAssertTrue(tracker.isPinnedToBottom)
    }

    func testAKeyboardReshapingTheThreadIsNeverBlamedOnTheReader() {
        let tracker = BottomPinTracker(tolerance: 64)
        tracker.record(ChatThreadMetrics(contentHeight: 1400, scrollOffset: 880, viewportHeight: viewport))
        let shrunk = tracker.record(ChatThreadMetrics(contentHeight: 1400, scrollOffset: 880,
                                                     viewportHeight: 300))
        XCTAssertFalse(shrunk.userMovedAwayFromBottom)
        XCTAssertTrue(tracker.isPinnedToBottom)
    }

    func testLiftingTheFingerAfterAnUpwardDragReleasesThePin() {
        let tracker = BottomPinTracker(tolerance: 64)
        tracker.record(metrics(content: 1400, offset: 880))
        tracker.dragChanged(translation: -580)
        tracker.record(metrics(content: 1400, offset: 300))
        let lifted = tracker.dragEnded()
        XCTAssertTrue(lifted.userMovedAwayFromBottom)
        XCTAssertFalse(tracker.isPinnedToBottom)
    }

    func testLiftingTheFingerOnTheBottomKeepsThePin() {
        let tracker = BottomPinTracker(tolerance: 64)
        tracker.record(metrics(content: 1400, offset: 880))
        tracker.dragChanged(translation: 0)
        let lifted = tracker.dragEnded()
        XCTAssertTrue(lifted.atBottom)
        XCTAssertTrue(tracker.isPinnedToBottom)
    }

    func testAnUpwardFingerReleasesThePinWhileTheThreadKeepsReshaping() {
        let tracker = BottomPinTracker(tolerance: 64)
        tracker.record(metrics(content: 1400, offset: 880))
        XCTAssertTrue(tracker.isPinnedToBottom)
        tracker.dragChanged(translation: -200)
        XCTAssertFalse(tracker.isPinnedToBottom,
                       "Die Fingerbewegung selbst sagt die Absicht, wachsender Verlauf darf sie nicht überdecken")
        XCTAssertTrue(tracker.record(metrics(content: 1600, offset: 400)).contentGrew)
        XCTAssertFalse(tracker.isPinnedToBottom)
    }

    func testADownwardFingerNeverReleasesThePin() {
        let tracker = BottomPinTracker(tolerance: 64)
        tracker.record(metrics(content: 1400, offset: 880))
        tracker.dragChanged(translation: 40)
        XCTAssertTrue(tracker.isPinnedToBottom)
        tracker.dragChanged(translation: -50)
        XCTAssertTrue(tracker.isPinnedToBottom, "Unter der Toleranz bleibt der Leser an der Nadel")
    }

    func testTheReaderIsNeverReleasedWhenHeMustNotBeInterrupted() {
        let tracker = BottomPinTracker(tolerance: 64, respectUserScroll: false)
        tracker.record(metrics(content: 1400, offset: 880))
        XCTAssertFalse(tracker.record(metrics(content: 1400, offset: 40)).userMovedAwayFromBottom)
        XCTAssertTrue(tracker.isPinnedToBottom)
        tracker.dragChanged(translation: -900)
        XCTAssertTrue(tracker.isPinnedToBottom)
        XCTAssertFalse(tracker.dragEnded().atBottom)
        XCTAssertTrue(tracker.isPinnedToBottom)
    }

    func testAFollowGluesTheThreadToTheNewestEntry() {
        let scroller = ChatAutoScroll(pins: BottomPinTracker(tolerance: 64))
        let recorder = ScrollRecorder()
        scroller.record(metrics(content: 1400, offset: 880), anchor: anchor, using: recorder.action)
        scroller.follow(anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, 1)
        XCTAssertEqual(recorder.lastAnchor, anchor)
        XCTAssertFalse(scroller.showsReturnToBottom)
    }

    func testNothingRollsWithoutAnAnchor() {
        let scroller = ChatAutoScroll(pins: BottomPinTracker(tolerance: 64))
        let recorder = ScrollRecorder()
        scroller.follow(nil, using: recorder.action)
        scroller.record(metrics(content: 1600, offset: 100), anchor: nil, using: recorder.action)
        XCTAssertEqual(recorder.calls, 0)
    }

    func testIdenticalReadingsNeverReannounceAnything() {
        let scroller = ChatAutoScroll(pins: BottomPinTracker(tolerance: 64))
        var signals = 0
        let token = scroller.objectWillChange.sink { _ in signals += 1 }
        let metric = ChatThreadMetrics(contentHeight: 1400, scrollOffset: 880, viewportHeight: 520)
        let recorder = ScrollRecorder()
        scroller.record(metric, anchor: anchor, using: recorder.action)
        let baseline = signals
        for _ in 0..<6 {
            scroller.record(metric, anchor: anchor, using: recorder.action)
            scroller.follow(anchor, using: recorder.action)
        }
        XCTAssertEqual(signals, baseline,
                       "gleiche Messung darf kein neues View-Update ausloesen — sonst dreht der Loop durch")
        token.cancel()
    }

    func testAnEntryArrivingWhileTheReaderIsUpstairsOnlyOffersTheWayBack() {
        let scroller = ChatAutoScroll(pins: BottomPinTracker(tolerance: 64))
        let recorder = ScrollRecorder()
        scroller.record(metrics(content: 1400, offset: 880), anchor: anchor, using: recorder.action)
        scroller.record(metrics(content: 1400, offset: 400), anchor: anchor, using: recorder.action)
        recorder.reset()
        scroller.follow(anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, 0, "Wer oben liest, wird nicht zurückgerissen")
        XCTAssertTrue(scroller.showsReturnToBottom)
    }

    func testContentThatGrowsLateIsFollowedBackToTheEnd() {
        let time = FakeTime()
        let scroller = timedScroller(time)
        let recorder = ScrollRecorder()
        scroller.record(metrics(content: 1400, offset: 880), anchor: anchor, using: recorder.action)
        time.advance(1)
        scroller.follow(anchor, using: recorder.action)
        time.advance(1)
        scroller.record(metrics(content: 1900, offset: 880), anchor: anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, 2, "Das spät geladene Bild zieht den Chat erneut ans Ende")
    }

    func testConvergenceRollsAreRateLimited() {
        let time = FakeTime()
        let scroller = timedScroller(time)
        let recorder = ScrollRecorder()
        scroller.record(metrics(content: 1600, offset: 100), anchor: anchor, using: recorder.action)
        let afterFirst = recorder.calls
        time.advance(0.05)
        scroller.record(metrics(content: 1600, offset: 300), anchor: anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, afterFirst, "Zwei Nachzüge im selben Takt bleiben einer")
        time.advance(1)
        scroller.record(metrics(content: 1600, offset: 900), anchor: anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, afterFirst + 1, "Ein Roll, der näher bringt, darf nach dem Takt erneut rollen")
    }

    func testNothingRollsWhileTheFingerIsOnTheGlass() {
        let time = FakeTime()
        let scroller = timedScroller(time)
        let recorder = ScrollRecorder()
        scroller.record(metrics(content: 1400, offset: 880), anchor: anchor, using: recorder.action)
        recorder.reset()
        scroller.dragChanged(translation: 0)
        time.advance(0.02)
        scroller.record(metrics(content: 1600, offset: 880), anchor: anchor, using: recorder.action)
        scroller.follow(anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, 0)
        time.advance(0.5)
        scroller.record(metrics(content: 1600, offset: 880), anchor: anchor, using: recorder.action)
        XCTAssertGreaterThan(recorder.calls, 0, "Nach dem Abheben holt der Chat auf")
    }

    func testARollThatBringsNothingCloserReleasesThePinInsteadOfRepeating() {
        let time = FakeTime()
        let pins = BottomPinTracker(tolerance: 64, now: time.reading)
        let scroller = ChatAutoScroll(pins: pins, now: time.reading)
        let recorder = ScrollRecorder()
        scroller.record(metrics(content: 3200, offset: 100), anchor: anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, 1)
        time.advance(0.2)
        scroller.record(metrics(content: 3200, offset: 105), anchor: anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, 2, "Näherkommen darf weiterfolgen")
        time.advance(0.2)
        scroller.record(metrics(content: 3200, offset: 105), anchor: anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, 2, "Ein Rollen ohne Näherkommen rollt nicht noch einmal")
        XCTAssertFalse(pins.isPinnedToBottom)
        XCTAssertTrue(scroller.showsReturnToBottom)
    }

    func testARollFromTheBottomIsNotHeldAgainstALaterGrowth() {
        let time = FakeTime()
        let pins = BottomPinTracker(tolerance: 64, now: time.reading)
        let scroller = ChatAutoScroll(pins: pins, now: time.reading)
        let recorder = ScrollRecorder()
        scroller.record(metrics(content: 1400, offset: 880), anchor: anchor, using: recorder.action)
        scroller.follow(anchor, using: recorder.action)
        time.advance(1)
        scroller.record(metrics(content: 1900, offset: 880), anchor: anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, 2, "Späteres Wachstum ist kein gescheiterter Nachzug")
        XCTAssertTrue(pins.isPinnedToBottom)
    }

    func testRollsThatConvergeKeepFollowingAllTheWayToTheEnd() {
        let time = FakeTime()
        let pins = BottomPinTracker(tolerance: 64, now: time.reading)
        let scroller = ChatAutoScroll(pins: pins, now: time.reading)
        let recorder = ScrollRecorder()
        scroller.record(metrics(content: 3200, offset: 100), anchor: anchor, using: recorder.action)
        time.advance(0.2)
        scroller.record(metrics(content: 3200, offset: 900), anchor: anchor, using: recorder.action)
        time.advance(0.2)
        scroller.record(metrics(content: 3200, offset: 1700), anchor: anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, 3)
        XCTAssertTrue(pins.isPinnedToBottom)
        XCTAssertFalse(scroller.showsReturnToBottom)
    }

    func testTheReturnButtonPinsAgainAndVanishes() {
        let pins = BottomPinTracker(tolerance: 64)
        let scroller = ChatAutoScroll(pins: pins)
        let recorder = ScrollRecorder()
        scroller.record(metrics(content: 1400, offset: 880), anchor: anchor, using: recorder.action)
        scroller.record(metrics(content: 1400, offset: 400), anchor: anchor, using: recorder.action)
        scroller.follow(anchor, using: recorder.action)
        XCTAssertTrue(scroller.showsReturnToBottom)
        recorder.reset()
        scroller.returnToBottom(anchor, using: recorder.action)
        XCTAssertTrue(pins.isPinnedToBottom)
        XCTAssertFalse(scroller.showsReturnToBottom)
        XCTAssertEqual(recorder.lastAnchor, anchor)
    }

    func testAnEntryThatArrivesDuringADragIsFinishedAfterTheLift() {
        let time = FakeTime()
        let scroller = timedScroller(time)
        let recorder = ScrollRecorder()
        scroller.record(metrics(content: 1400, offset: 880), anchor: anchor, using: recorder.action)
        scroller.dragChanged(translation: 0)
        time.advance(0.02)
        scroller.record(metrics(content: 1700, offset: 880), anchor: anchor, using: recorder.action)
        scroller.follow(anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, 0)
        time.advance(0.5)
        scroller.dragEnded(anchor, using: recorder.action)
        XCTAssertEqual(recorder.calls, 1)
        XCTAssertFalse(scroller.showsReturnToBottom)
    }

    func testAConversationSwitchStartsWithAFreshPin() {
        let pins = BottomPinTracker(tolerance: 64)
        let scroller = ChatAutoScroll(pins: pins)
        let recorder = ScrollRecorder()
        scroller.record(metrics(content: 1400, offset: 880), anchor: anchor, using: recorder.action)
        scroller.record(metrics(content: 1400, offset: 400), anchor: anchor, using: recorder.action)
        XCTAssertFalse(pins.isPinnedToBottom)
        recorder.reset()
        scroller.reset(anchor, using: recorder.action)
        XCTAssertTrue(pins.isPinnedToBottom)
        XCTAssertFalse(scroller.showsReturnToBottom)
        XCTAssertEqual(recorder.calls, 1)
    }

    private func metrics(content: CGFloat, offset: CGFloat) -> ChatThreadMetrics {
        ChatThreadMetrics(contentHeight: content, scrollOffset: offset, viewportHeight: viewport)
    }
}
