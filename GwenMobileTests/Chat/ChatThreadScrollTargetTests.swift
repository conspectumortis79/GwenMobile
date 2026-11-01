@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
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

    private func stageView() throws -> UIView {
        if let stage = Self.stage, stage.window != nil {
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
        try await settle()
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
        try await settle()
        let tracker = BottomPinTracker(tolerance: 64)
        let atTop = try XCTUnwrap(probe.metrics.value)
        tracker.record(atTop)
        probe.proxy.value?.scrollTo("msg-line-24", anchor: .bottom)
        try await settle()
        let rolled = try XCTUnwrap(probe.metrics.value)
        XCTAssertGreaterThan(rolled.scrollOffset, atTop.scrollOffset)
        XCTAssertFalse(tracker.record(rolled).userMovedAwayFromBottom,
                       "der eigene Nachzug ans Ende ist keine Leserflucht")
        XCTAssertTrue(tracker.isPinnedToBottom)
    }

    func testAReaderWhoScrollsUpInTheRealThreadReleasesThePin() async throws {
        let probe = try await host(marked: true)
        probe.proxy.value?.scrollTo("msg-line-24", anchor: .bottom)
        try await settle()
        let tracker = BottomPinTracker(tolerance: 64)
        XCTAssertTrue(tracker.record(try XCTUnwrap(probe.metrics.value)).atBottom)
        probe.scroll.setContentOffset(CGPoint(x: 0, y: probe.scroll.contentOffset.y - 500), animated: false)
        try await settle()
        let upstairs = try XCTUnwrap(probe.metrics.value)
        XCTAssertTrue(tracker.record(upstairs).userMovedAwayFromBottom)
        XCTAssertFalse(tracker.isPinnedToBottom)
    }

    func testTheRealScrollerGluesTheThreadToRowsThatArriveLate() async throws {
        let box = MetricsBox()
        let (model, _, _) = try await autoThread(box: box)
        model.lines.append(contentsOf: (25...44).map { Line(index: $0) })
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(try XCTUnwrap(box.value).distanceToBottom, 0, accuracy: 1,
                       "spaet angekommene Zeilen muessen bis unters Ende nachgezogen werden")
    }

    func testTheRealScrollerNeverYanksAReaderWhoWentUpstairs() async throws {
        let box = MetricsBox()
        let (model, host, scroller) = try await autoThread(box: box)
        let scroll = try XCTUnwrap(Self.scrollView(in: host.view))
        scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentOffset.y - 600), animated: false)
        try await settle()
        let before = try XCTUnwrap(box.value)
        model.lines.append(contentsOf: (25...44).map { Line(index: $0) })
        try await Task.sleep(for: .milliseconds(700))
        let after = try XCTUnwrap(box.value)
        XCTAssertLessThanOrEqual(after.scrollOffset, before.scrollOffset + 1,
                                 "wer oben liest, darf nicht nach unten gerissen werden")
        XCTAssertTrue(scroller.showsReturnToBottom)
    }

    private func autoThread(box: MetricsBox) async throws -> (model: Model, host: UIHostingController<AutoThread>,
                                                              scroller: ChatAutoScroll) {
        let scroller = ChatAutoScroll(pins: BottomPinTracker(tolerance: 64))
        let model = Model((1...24).map { Line(index: $0) })
        let host = UIHostingController(rootView: AutoThread(model: model, scroller: scroller,
                                                           onMetrics: { box.value = $0 }))
        try mount(host)
        try await settle()
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
        try await settle()
        let before = probe.scroll.contentOffset.y
        probe.proxy.value?.scrollTo(target, anchor: .bottom)
        try await settle()
        return probe.scroll.contentOffset.y - before > 1
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(250))
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
