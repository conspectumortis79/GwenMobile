@testable import GwenMobileFeatureCore
import XCTest
import SwiftUI
import GwenMobileKit

@MainActor
final class ChatThreadScrollTargetTests: XCTestCase {
    private struct Line: Identifiable {
        let index: Int
        var id: String { "msg-line-\(index)" }
        var text: String { "Zeile \(index)" }
    }

    @MainActor
    private final class MetricsBox {
        var value: ChatThreadMetrics?
    }

    @MainActor
    private final class ProxyBox {
        var value: ScrollViewProxy?
    }

    @MainActor
    private final class Model: ObservableObject {
        @Published var lines: [Line]

        init(_ lines: [Line]) { self.lines = lines }

        var lastAnchor: AnyHashable? { lines.last.map { AnyHashable($0.id) } }
    }

    private struct Thread: View {
        @ObservedObject var model: Model
        let marked: Bool
        let onMetrics: (ChatThreadMetrics) -> Void
        let onRegister: (ScrollViewProxy) -> Void

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.lines) { line in
                            if marked {
                                Text(line.text).frame(height: 60).id(line.id)
                            } else {
                                Text(line.text).frame(height: 60)
                            }
                        }
                    }
                    .background(ChatThreadMetricsReader(onMetrics: onMetrics))
                }
                .onAppear { onRegister(proxy) }
            }
        }
    }

    private struct AutoThread: View {
        @ObservedObject var model: Model
        let scroller: ChatAutoScroll
        let onMetrics: (ChatThreadMetrics) -> Void

        private func action(_ proxy: ScrollViewProxy) -> ChatAutoScroll.ScrollAction {
            { anchor in proxy.scrollTo(anchor, anchor: .bottom) }
        }

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.lines) { line in
                            Text(line.text).frame(height: 60).id(line.id)
                        }
                    }
                    .background(ChatThreadMetricsReader { metrics in
                        onMetrics(metrics)
                        scroller.record(metrics, anchor: model.lastAnchor, using: action(proxy))
                    })
                }
                .onAppear { scroller.follow(model.lastAnchor, using: action(proxy)) }
                .onChange(of: model.lines.count) { _, _ in
                    scroller.follow(model.lastAnchor, using: action(proxy))
                }
            }
        }
    }

    private struct Probe {
        let scroll: UIScrollView
        let metrics: MetricsBox
        let proxy: ProxyBox
    }

    private static weak var stage: UIView?

    override func tearDown() async throws {
        Self.stage?.subviews.forEach { $0.removeFromSuperview() }
        Self.stage?.removeFromSuperview()
        Self.stage = nil
        try await super.tearDown()
    }

    private func stageView() throws -> UIView {
        if let stage = Self.stage, stage.window != nil {
            stage.frame = stage.window?.bounds ?? stage.frame
            stage.subviews.forEach { $0.removeFromSuperview() }
            return stage
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let holder = UIView(frame: window.bounds)
        holder.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(holder)
        Self.stage = holder
        return holder
    }

    func testTheReaderReportsTheRealGeometryOfTheThread() async throws {
        let probe = try await host(marked: true)
        let metrics = try XCTUnwrap(probe.metrics.value, "der Reader meldet überhaupt nichts")
        let scroll = probe.scroll
        XCTAssertEqual(metrics.contentHeight, scroll.contentSize.height, accuracy: 1,
                       "der Reader muss die echte Fadenhoehe melden")
        XCTAssertEqual(metrics.viewportHeight, scroll.bounds.height, accuracy: 1)
        XCTAssertEqual(metrics.scrollOffset, scroll.contentOffset.y, accuracy: 1,
                       "der Reader muss den echten Rollenversatz melden")
        XCTAssertEqual(metrics.distanceToBottom,
                       max(0, scroll.contentSize.height - scroll.bounds.height - scroll.contentOffset.y),
                       accuracy: 1)
    }

    func testOnlyRealRowsAreScrollTargetsAndTheGhostProvesTheMeasurement() async throws {
        let marked = try await host(marked: true)
        let ghost = try await rolled(marked, to: "msg-line-999")
        let real = try await rolled(marked, to: "msg-line-24")
        XCTAssertFalse(ghost, "ein nicht vorhandenes Ziel darf nichts bewegen")
        XCTAssertTrue(real)

        let plain = try await host(marked: false)
        let plainTarget = try await rolled(plain, to: "msg-line-24")
        XCTAssertTrue(plainTarget, "die ForEach-Identitaet der Zeilen reicht ebenfalls als Ziel")
    }

    func testAnAutomaticRollDownIsNotCountedAsAReaderEscaping() async throws {
        let probe = try await host(marked: true)
        probe.scroll.setContentOffset(.zero, animated: false)
        let reset = await waitUntil { (probe.metrics.value?.scrollOffset ?? 1000) <= 1 }
        XCTAssertTrue(reset, "der Faden springt nicht an den Anfang")
        let tracker = BottomPinTracker(tolerance: 64)
        let atTop = try XCTUnwrap(probe.metrics.value)
        tracker.record(atTop)
        probe.proxy.value?.scrollTo("msg-line-24", anchor: .bottom)
        let moved = await waitUntil(.seconds(3)) {
            (probe.metrics.value?.scrollOffset ?? 0) > atTop.scrollOffset + 1
        }
        XCTAssertTrue(moved, "der eigene Nachzug bewegt den Faden nicht")
        let rolled = try XCTUnwrap(probe.metrics.value)
        XCTAssertGreaterThan(rolled.scrollOffset, atTop.scrollOffset)
        XCTAssertFalse(tracker.record(rolled).userMovedAwayFromBottom,
                       "der eigene Nachzug ans Ende ist keine Leserflucht")
        XCTAssertTrue(tracker.isPinnedToBottom)
    }

    func testAReaderWhoScrollsUpInTheRealThreadReleasesThePin() async throws {
        let probe = try await host(marked: true)
        probe.proxy.value?.scrollTo("msg-line-24", anchor: .bottom)
        let reachedBottom = await waitUntil(.seconds(3)) {
            (probe.metrics.value?.distanceToBottom ?? 1000) <= 64
        }
        XCTAssertTrue(reachedBottom, "der Faden erreicht den Boden nicht")
        let tracker = BottomPinTracker(tolerance: 64)
        XCTAssertTrue(tracker.record(try XCTUnwrap(probe.metrics.value)).atBottom)
        let bottom = probe.scroll.contentOffset.y
        probe.scroll.setContentOffset(CGPoint(x: 0, y: bottom - 500), animated: false)
        let movedUp = await waitUntil(.seconds(2)) {
            (probe.metrics.value?.scrollOffset ?? bottom) <= bottom - 400
        }
        XCTAssertTrue(movedUp, "der Rollenversatz kommt nicht an")
        let upstairs = try XCTUnwrap(probe.metrics.value)
        XCTAssertTrue(tracker.record(upstairs).userMovedAwayFromBottom)
        XCTAssertFalse(tracker.isPinnedToBottom)
    }

    func testTheRealScrollerGluesTheThreadToRowsThatArriveLate() async throws {
        let box = MetricsBox()
        let (model, _, _) = try await autoThread(box: box)
        let before = try XCTUnwrap(box.value)
        model.lines.append(contentsOf: (25...44).map { Line(index: $0) })
        let grew = await waitUntil(.seconds(3)) {
            (box.value?.contentHeight ?? before.contentHeight) > before.contentHeight + 1
        }
        XCTAssertTrue(grew, "die neuen Zeilen kommen nicht an")
        let atBottom = await waitUntil(.seconds(3)) {
            abs(box.value?.distanceToBottom ?? 1000) <= 1
        }
        XCTAssertTrue(atBottom, "spaet angekommene Zeilen muessen bis unters Ende nachgezogen werden")
        XCTAssertEqual(try XCTUnwrap(box.value).distanceToBottom, 0, accuracy: 1)
    }

    func testTheRealScrollerNeverYanksAReaderWhoWentUpstairs() async throws {
        let box = MetricsBox()
        let (model, host, scroller) = try await autoThread(box: box)
        let scroll = try XCTUnwrap(Self.scrollView(in: host.view))
        let top = scroll.contentOffset.y
        scroll.setContentOffset(CGPoint(x: 0, y: max(0, top - 600)), animated: false)
        let shifted = await waitUntil(.seconds(2)) {
            abs((box.value?.scrollOffset ?? top) - scroll.contentOffset.y) <= 1
        }
        XCTAssertTrue(shifted, "der Rollenversatz kommt nicht an")
        let before = try XCTUnwrap(box.value)
        model.lines.append(contentsOf: (25...44).map { Line(index: $0) })
        let grew = await waitUntil(.seconds(3)) {
            (box.value?.contentHeight ?? before.contentHeight) > before.contentHeight + 1
        }
        XCTAssertTrue(grew, "die neuen Zeilen kommen nicht an")
        let stayed = await waitUntil(.seconds(3)) {
            (box.value?.scrollOffset ?? before.scrollOffset + 1000) <= before.scrollOffset + 1
        }
        XCTAssertTrue(stayed, "wer oben liest, darf nicht nach unten gerissen werden")
        let returned = await waitUntil(.seconds(3)) { scroller.showsReturnToBottom }
        XCTAssertTrue(returned, "der Zurueck-Knopf erscheint nicht")
        let after = try XCTUnwrap(box.value)
        XCTAssertLessThanOrEqual(after.scrollOffset, before.scrollOffset + 1,
                                 "wer oben liest, darf nicht nach unten gerissen werden")
    }

    private func autoThread(box: MetricsBox) async throws -> (model: Model, host: UIHostingController<AutoThread>,
                                                              scroller: ChatAutoScroll) {
        let scroller = ChatAutoScroll(pins: BottomPinTracker(tolerance: 64))
        let model = Model((1...24).map { Line(index: $0) })
        let host = UIHostingController(rootView: AutoThread(model: model, scroller: scroller,
                                                           onMetrics: { box.value = $0 }))
        try mount(host)
        let ready = await waitUntil(.seconds(3)) { box.value != nil }
        XCTAssertTrue(ready, "der Auto-Thread meldet keine Metriken")
        let pinned = await waitUntil(.seconds(3)) {
            (box.value?.distanceToBottom ?? 1000) <= 1
        }
        XCTAssertTrue(pinned, "der Auto-Thread startet nicht am Ende")
        return (model, host, scroller)
    }

    private func host(marked: Bool) async throws -> Probe {
        let metrics = MetricsBox()
        let proxy = ProxyBox()
        let model = Model((1...24).map { Line(index: $0) })
        let host = UIHostingController(rootView: Thread(model: model, marked: marked,
                                                       onMetrics: { metrics.value = $0 },
                                                       onRegister: { proxy.value = $0 }))
        try mount(host)
        let scroll = try XCTUnwrap(Self.scrollView(in: host.view), "kein UIScrollView im gehosteten Faden")
        let ready = await waitUntil(.seconds(3)) { metrics.value != nil && proxy.value != nil }
        XCTAssertTrue(ready, "Reader oder Proxy melden sich nicht")
        let sized = await waitUntil(.seconds(3)) {
            scroll.contentSize.height > scroll.bounds.height
        }
        XCTAssertTrue(sized, "der Faden hat keine Rollflaeche")
        return Probe(scroll: scroll, metrics: metrics, proxy: proxy)
    }

    private func mount(_ host: UIHostingController<some View>) throws {
        let stage = try stageView()
        host.view.frame = CGRect(x: 0, y: 0, width: stage.bounds.width, height: 320)
        stage.addSubview(host.view)
        stage.layoutIfNeeded()
    }

    private func rolled(_ probe: Probe, to target: String) async throws -> Bool {
        probe.scroll.setContentOffset(.zero, animated: false)
        _ = await waitUntil { abs(probe.scroll.contentOffset.y) <= 1 }
        let before = probe.scroll.contentOffset.y
        probe.proxy.value?.scrollTo(target, anchor: .bottom)
        return await waitUntil(.seconds(2)) { probe.scroll.contentOffset.y - before > 1 }
    }

    private func waitUntil(_ timeout: Duration = .seconds(2),
                           _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private static func scrollView(in view: UIView, depth: Int = 0) -> UIScrollView? {
        guard depth < 30 else { return nil }
        if let match = view as? UIScrollView, !(match is UITableView), !(match is UICollectionView) {
            return match
        }
        for child in view.subviews {
            if let found = scrollView(in: child, depth: depth + 1) { return found }
        }
        return nil
    }
}
