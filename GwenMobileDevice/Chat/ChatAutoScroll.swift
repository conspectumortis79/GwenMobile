@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

enum ChatScrollAnchors {
    static let streaming = "streaming"
    static let imageWorking = "image_working"
    static let asrWorking = "asr_working"
    static let webStatus = "web_status"

    static func message(_ id: UUID) -> String { "msg-\(id.uuidString)" }

    static func bottom(lastMessageID: UUID?, statusRows: [ChatThreadStatusRow]) -> AnyHashable? {
        if let row = statusRows.last { return AnyHashable(row.id) }
        return lastMessageID.map { AnyHashable(message($0)) }
    }
}

struct ChatThreadObservation: Equatable {
    var atBottom = false
    var contentGrew = false
    var userMovedAwayFromBottom = false
    var distanceToBottom: CGFloat = 0
}

@MainActor
final class BottomPinTracker {
    static let dragStall: TimeInterval = 0.35
    static let geometryEpsilon: CGFloat = 1

    let tolerance: CGFloat
    private let respectUserScroll: Bool
    private let now: @MainActor () -> Date
    private var last: ChatThreadMetrics?
    private var lastDragChange: Date = .distantPast
    private var dragStartOffset: CGFloat?

    private(set) var isPinnedToBottom = true

    var currentMetrics: ChatThreadMetrics? { last }

    init(tolerance: CGFloat, respectUserScroll: Bool = true,
         now: @escaping @MainActor () -> Date = Date.init) {
        self.tolerance = tolerance
        self.respectUserScroll = respectUserScroll
        self.now = now
    }

    var isUserDragging: Bool {
        now().timeIntervalSince(lastDragChange) < Self.dragStall
    }

    @discardableResult
    func record(_ metrics: ChatThreadMetrics) -> ChatThreadObservation {
        let previous = last
        last = metrics
        if isUserDragging {
            if dragStartOffset == nil { dragStartOffset = metrics.scrollOffset }
        } else {
            dragStartOffset = nil
        }
        let atBottom = metrics.distanceToBottom <= tolerance
        let movedAway = scrolledUp(previous: previous, current: metrics)
        if atBottom { isPinnedToBottom = true }
        else if movedAway { isPinnedToBottom = false }
        return ChatThreadObservation(
            atBottom: atBottom,
            contentGrew: grew(previous: previous, current: metrics),
            userMovedAwayFromBottom: movedAway,
            distanceToBottom: metrics.distanceToBottom
        )
    }

    func dragChanged(translation: CGFloat) {
        lastDragChange = now()
        if dragStartOffset == nil { dragStartOffset = last?.scrollOffset }
        if respectUserScroll, translation < -tolerance { isPinnedToBottom = false }
    }

    func unpin() {
        dragStartOffset = nil
        lastDragChange = .distantPast
        isPinnedToBottom = false
    }

    func dragEnded() -> ChatThreadObservation {
        let started = dragStartOffset
        dragStartOffset = nil
        lastDragChange = .distantPast
        let current = last ?? ChatThreadMetrics()
        let atBottom = current.distanceToBottom <= tolerance
        let movedAway = respectUserScroll && started.map { current.scrollOffset < $0 - tolerance } == true
        if atBottom { isPinnedToBottom = true }
        else if movedAway { isPinnedToBottom = false }
        return ChatThreadObservation(atBottom: atBottom, contentGrew: false,
                                     userMovedAwayFromBottom: movedAway,
                                     distanceToBottom: current.distanceToBottom)
    }

    func pin() {
        dragStartOffset = nil
        lastDragChange = .distantPast
        isPinnedToBottom = true
    }

    func reset() {
        last = nil
        pin()
    }

    private func scrolledUp(previous: ChatThreadMetrics?, current: ChatThreadMetrics) -> Bool {
        guard respectUserScroll, let previous else { return false }
        guard previous.scrollOffset - current.scrollOffset > tolerance else { return false }
        return abs(current.contentHeight - previous.contentHeight) <= Self.geometryEpsilon
            && abs(current.viewportHeight - previous.viewportHeight) <= Self.geometryEpsilon
    }

    private func grew(previous: ChatThreadMetrics?, current: ChatThreadMetrics) -> Bool {
        guard let previous else { return false }
        return current.contentHeight - previous.contentHeight > Self.geometryEpsilon
    }
}

@MainActor
final class ChatAutoScroll: ObservableObject {
    typealias ScrollAction = @MainActor (AnyHashable) -> Void

    static let tolerance: CGFloat = 64
    static let convergenceInterval: TimeInterval = 0.15
    static let dragThreshold: CGFloat = 10
    static let rollProgressEpsilon: CGFloat = 2

    @Published private var returnVisible = false

    private let pins: BottomPinTracker
    private let now: @MainActor () -> Date
    private var lastConvergence: Date = .distantPast
    private var pendingAnchor: AnyHashable?
    private var lastDistance: CGFloat?
    private var pendingRollDistance: CGFloat?
    #if DEBUG
    private var lastContent: ChatThreadMetrics?
    #endif

    init(pins: BottomPinTracker = BottomPinTracker(tolerance: ChatAutoScroll.tolerance),
         now: @escaping @MainActor () -> Date = Date.init) {
        self.pins = pins
        self.now = now
    }

    var showsReturnToBottom: Bool { returnVisible }

    func follow(_ anchor: AnyHashable?, using scroll: ScrollAction) {
        guard pins.isPinnedToBottom else {
            setReturnVisible(anchor != nil)
            return
        }
        guard !pins.isUserDragging else {
            pendingAnchor = anchor ?? pendingAnchor
            return
        }
        lastConvergence = now()
        rollTo(anchor, using: scroll)
    }

    func record(_ metrics: ChatThreadMetrics, anchor: AnyHashable?, using scroll: ScrollAction) {
        #if DEBUG
        noteContentChange(metrics)
        #endif
        let observation = pins.record(metrics)
        lastDistance = observation.distanceToBottom
        if observation.atBottom {
            pendingRollDistance = nil
            setReturnVisible(false)
        }
        if let aimed = pendingRollDistance {
            pendingRollDistance = nil
            if observation.distanceToBottom >= aimed - Self.rollProgressEpsilon {
                pins.unpin()
                setReturnVisible(true)
                #if DEBUG
                flowMark("AUTOSCROLL roll_vergeblich ziel=\(Int(aimed)) jetzt=\(Int(observation.distanceToBottom)) → nadel gelöst")
                #endif
                return
            }
        }
        if observation.contentGrew && !pins.isPinnedToBottom { setReturnVisible(true) }
        guard pins.isPinnedToBottom, !pins.isUserDragging,
              observation.distanceToBottom > pins.tolerance else { return }
        let date = now()
        guard date.timeIntervalSince(lastConvergence) >= Self.convergenceInterval else { return }
        lastConvergence = date
        #if DEBUG
        flowMark("AUTOSCROLL roll abstand=\(Int(observation.distanceToBottom)) "
            + "nadel=\(pins.isPinnedToBottom) wachsend=\(observation.contentGrew) anlass=record")
        #endif
        rollTo(anchor, using: scroll)
    }

    func dragChanged(translation: CGFloat) {
        #if DEBUG
        let began = !pins.isUserDragging
        #endif
        pins.dragChanged(translation: translation)
        #if DEBUG
        if began, let metrics = pins.currentMetrics {
            flowMark("AUTOSCROLL drag_start offset=\(Int(metrics.scrollOffset)) "
                + "viewport=\(Int(metrics.viewportHeight)) pinned=\(pins.isPinnedToBottom)")
        }
        #endif
    }

    func dragEnded(_ anchor: AnyHashable?, using scroll: ScrollAction) {
        let observation = pins.dragEnded()
        #if DEBUG
        flowMark("AUTOSCROLL drag_end weg=\(observation.userMovedAwayFromBottom) "
            + "unten=\(observation.atBottom) abstand=\(Int(observation.distanceToBottom)) "
            + "nadel=\(pins.isPinnedToBottom)")
        #endif
        if observation.atBottom { setReturnVisible(false) }
        guard pins.isPinnedToBottom else {
            setReturnVisible(returnVisible || pendingAnchor != nil)
            pendingAnchor = nil
            return
        }
        pendingAnchor = nil
        guard observation.distanceToBottom > pins.tolerance else { return }
        lastConvergence = now()
        #if DEBUG
        flowMark("AUTOSCROLL roll anker=\(anchor.map { "\($0)" } ?? "-") abstand=\(Int(observation.distanceToBottom)) anlass=drag_end")
        #endif
        rollTo(anchor, using: scroll)
    }

    func returnToBottom(_ anchor: AnyHashable?, using scroll: ScrollAction) {
        pins.pin()
        rollToTheEnd(anchor, using: scroll)
    }

    func reset(_ anchor: AnyHashable?, using scroll: ScrollAction) {
        pins.reset()
        rollToTheEnd(anchor, using: scroll)
    }

    private func rollToTheEnd(_ anchor: AnyHashable?, using scroll: ScrollAction) {
        pendingAnchor = nil
        pendingRollDistance = nil
        setReturnVisible(false)
        lastConvergence = now()
        scrollIfNeeded(to: anchor, using: scroll)
    }

    private func scrollIfNeeded(to anchor: AnyHashable?, using scroll: ScrollAction) {
        guard let anchor else { return }
        scroll(anchor)
    }

    private func rollTo(_ anchor: AnyHashable?, using scroll: ScrollAction) {
        let aimed = lastDistance ?? 0
        pendingRollDistance = aimed > pins.tolerance ? aimed : nil
        scrollIfNeeded(to: anchor, using: scroll)
    }

    private func setReturnVisible(_ visible: Bool) {
        guard returnVisible != visible else { return }
        returnVisible = visible
    }

    #if DEBUG
    private func noteContentChange(_ metrics: ChatThreadMetrics) {
        let previous = lastContent
        defer { lastContent = metrics }
        guard let previous,
              abs(metrics.contentHeight - previous.contentHeight) > 1
                || abs(metrics.contentWidth - previous.contentWidth) > 1 else { return }
        flowMark("METRIK Δh=\(Int(metrics.contentHeight - previous.contentHeight)) "
            + "Δb=\(Int(metrics.contentWidth - previous.contentWidth)) "
            + "höhe=\(Int(metrics.contentHeight)) breite=\(Int(metrics.contentWidth)) "
            + "versatz=\(Int(metrics.scrollOffset)) "
            + "viewport=\(Int(metrics.viewportHeight))x\(Int(metrics.viewportWidth)) "
            + "inset=\(Int(metrics.bottomInset))")
    }
    #endif
}

struct ReturnToBottomButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                Text(L.t("scroll_to_bottom"))
            }
            .scaledFont(13, weight: .medium)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(.thinMaterial))
            .overlay(Capsule().strokeBorder(Color(.systemGray4), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.14), radius: 7, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("scroll_to_bottom"))
    }
}
