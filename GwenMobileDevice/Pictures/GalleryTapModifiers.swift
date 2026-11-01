@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit

@MainActor
final class TapModifierProbe {
    private var flags: UIKeyModifierFlags = []

    var mode: GalleryTapMode {
        if flags.contains(.command) { return .adding }
        if flags.contains(.shift) { return .range }
        if flags.contains(.alternate) { return .saving }
        return .plain
    }

    func note(_ received: UIKeyModifierFlags) {
        flags = received
    }
}

struct GalleryTapModifiers: UIViewRepresentable {
    let probe: TapModifierProbe

    func makeUIView(context: Context) -> GalleryTapProbeView {
        let view = GalleryTapProbeView()
        view.onFlags = { [probe] received in probe.note(received) }
        return view
    }

    func updateUIView(_ uiView: GalleryTapProbeView, context: Context) {
        uiView.onFlags = { [probe] received in probe.note(received) }
    }
}

final class GalleryTapProbeView: UIView {
    var onFlags: (@MainActor (UIKeyModifierFlags) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        onFlags?(event?.modifierFlags ?? [])
    }
}
