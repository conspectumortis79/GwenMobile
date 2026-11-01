@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

struct ProcessingRhythm {
    static let dotCount: Int = 3
    static let beat: Double = 0.5
    static let fade: Double = 0.2
    static let retract: Double = 0.16
    static let lead: Double = 0.1

    static func hiddenDuration(dotIndex: Int) -> Double {
        beat * Double(dotIndex) - lead
    }

    static func holdDuration(dotIndex: Int) -> Double {
        beat * Double(dotCount + 1 - dotIndex) - lead - retract
    }
}

struct ProcessingDots: View {
    private struct Fill {
        var first: Double = 0
        var second: Double = 0
        var third: Double = 0
    }

    private enum Geometry {
        static let size: CGFloat = 6
        static let gap: CGFloat = 4
        static let width: CGFloat = size * CGFloat(ProcessingRhythm.dotCount) + gap * (CGFloat(ProcessingRhythm.dotCount) - 1)
    }

    nonisolated(unsafe) static var reduceMotionOverride: @MainActor @Sendable () -> Bool = {
        UIAccessibility.isReduceMotionEnabled
    }

    var tint: Color = Color(.secondaryLabel)
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion: Bool

    private var reduceMotion: Bool { systemReduceMotion || Self.reduceMotionOverride() }

    var body: some View {
        if reduceMotion {
            row(Fill(first: 1, second: 1, third: 1))
        } else {
            KeyframeAnimator(initialValue: Fill(), repeating: true) { fill in
                row(fill)
            } keyframes: { _ in
                track(\.first, dotIndex: 1)
                track(\.second, dotIndex: 2)
                track(\.third, dotIndex: 3)
            }
        }
    }

    private func row(_ fill: Fill) -> some View {
        HStack(spacing: Geometry.gap) {
            dot(fill.first)
            dot(fill.second)
            dot(fill.third)
        }
        .frame(width: Geometry.width, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func dot(_ level: Double) -> some View {
        Circle()
            .fill(tint)
            .frame(width: Geometry.size, height: Geometry.size)
            .opacity(level)
            .scaleEffect(0.4 + 0.6 * level)
    }

    private func track(_ keyPath: WritableKeyPath<Fill, Double>,
                       dotIndex: Int) -> some Keyframes<Fill> {
        KeyframeTrack(keyPath) {
            LinearKeyframe(0.0, duration: ProcessingRhythm.hiddenDuration(dotIndex: dotIndex))
            CubicKeyframe(1.0, duration: ProcessingRhythm.fade)
            LinearKeyframe(1.0, duration: ProcessingRhythm.holdDuration(dotIndex: dotIndex))
            CubicKeyframe(0.0, duration: ProcessingRhythm.retract)
        }
    }
}

struct ProcessingLabel: View {
    let text: String
    var size: CGFloat = 17
    var weight: Font.Weight = .regular
    var lineLimit: Int? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .scaledFont(size, weight: weight)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
            ProcessingDots()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
