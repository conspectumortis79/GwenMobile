@testable import GwenMobileFeatureCore
#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

extension View {
    @ViewBuilder func suppressingTextFocusRing() -> some View {
        background(alignment: .center) { TextFocusRingGuard() }
    }
}

struct TextFocusRingGuard: UIViewRepresentable {
    func makeUIView(context: Context) -> TextFocusRingSuppressingView {
        TextFocusRingSuppressingView()
    }

    func updateUIView(_ uiView: TextFocusRingSuppressingView, context: Context) {
        uiView.requestSweep()
    }
}

final class TextFocusRingSuppressingView: UIView {
    private var sweepScheduled = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        requestSweep()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        requestSweep()
    }

    func requestSweep() {
        guard !sweepScheduled else { return }
        sweepScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let view = self else { return }
            view.sweepScheduled = false
            TextSelectionFocusRings.suppress(around: view)
        }
    }
}

@MainActor
enum TextSelectionFocusRings {
    private static let selectedTextRange = NSSelectorFromString("selectedTextRange")
    private static let maxAncestorDepth = 4

    static func suppress(around view: UIView) {
        var ancestor = view.superview
        var depth = 0
        while let current = ancestor, depth < maxAncestorDepth {
            let hosts = selectionHosts(in: current)
            if !hosts.isEmpty {
                for host in hosts where host.focusEffect != nil {
                    host.focusEffect = nil
                }
                return
            }
            ancestor = current.superview
            depth += 1
        }
    }

    private static func selectionHosts(in view: UIView) -> [UIView] {
        var hosts: [UIView] = []
        for child in view.subviews {
            if child.canBecomeFocused, child.responds(to: selectedTextRange) {
                hosts.append(child)
            }
            hosts.append(contentsOf: selectionHosts(in: child))
        }
        return hosts
    }
}
#else
import SwiftUI

extension View {
    @ViewBuilder func suppressingTextFocusRing() -> some View { self }
}
#endif
