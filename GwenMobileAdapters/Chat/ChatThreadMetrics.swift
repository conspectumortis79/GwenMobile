import GwenMobileKit
import SwiftUI
import UIKit

struct ChatThreadMetrics: Equatable {
    var contentHeight: CGFloat = 0
    var contentWidth: CGFloat = 0
    var scrollOffset: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var viewportWidth: CGFloat = 0
    var bottomInset: CGFloat = 0

    var distanceToBottom: CGFloat {
        max(0, contentHeight + bottomInset - scrollOffset - viewportHeight)
    }
}

@MainActor
final class ThreadMetricsView: UIView {
    var onMetrics: ((ChatThreadMetrics) -> Void)?

    private weak var scroll: UIScrollView?
    private var tokens: [NSKeyValueObservation] = []
    private var queued = false
    private var published: ChatThreadMetrics?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        watch()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        watch()
    }

    func publishNow() {
        guard let scroll else { return }
        let metrics = ChatThreadMetrics(contentHeight: scroll.contentSize.height,
                                        contentWidth: scroll.contentSize.width,
                                        scrollOffset: scroll.contentOffset.y,
                                        viewportHeight: scroll.bounds.height,
                                        viewportWidth: scroll.bounds.width,
                                        bottomInset: scroll.adjustedContentInset.bottom)
        #if DEBUG
        if metrics.viewportWidth < 100 || metrics.contentWidth < 100 {
            flowMark("RAHMEN viewport=\(Int(metrics.viewportWidth))x\(Int(metrics.viewportHeight)) "
                + "inhalt=\(Int(metrics.contentWidth))x\(Int(metrics.contentHeight))")
        }
        #endif
        guard metrics != published else { return }
        published = metrics
        onMetrics?(metrics)
    }

    private func watch() {
        guard let match = Self.enclosingScrollView(of: self) else { return }
        if scroll === match { return }
        scroll = match
        tokens = [observing(match, \.contentOffset),
                  observing(match, \.contentSize),
                  observing(match, \.adjustedContentInset),
                  observing(match, \.frame)]
        queue()
    }

    private func observing<Value>(_ target: UIScrollView,
                                  _ keyPath: KeyPath<UIScrollView, Value>) -> NSKeyValueObservation {
        target.observe(keyPath) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.queue() }
        }
    }

    private func queue() {
        guard !queued else { return }
        queued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.queued = false
            self.publishNow()
        }
    }

    private static func enclosingScrollView(of view: UIView) -> UIScrollView? {
        var walker = view.superview
        while let current = walker {
            if let scroll = current as? UIScrollView { return scroll }
            walker = current.superview
        }
        return nil
    }
}

struct ChatThreadMetricsReader: UIViewRepresentable {
    var onMetrics: (ChatThreadMetrics) -> Void

    func makeUIView(context: Context) -> ThreadMetricsView {
        let view = ThreadMetricsView(frame: .zero)
        view.onMetrics = onMetrics
        return view
    }

    func updateUIView(_ view: ThreadMetricsView, context: Context) {
        view.onMetrics = onMetrics
        view.setNeedsLayout()
    }
}
