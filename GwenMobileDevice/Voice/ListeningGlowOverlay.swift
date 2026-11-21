import Foundation
import SwiftUI

struct ListeningGlowOverlay: View {
    let phase: ListenGlowPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            glow(time: context.date.timeIntervalSinceReferenceDate)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }

    private func glow(time: TimeInterval) -> some View {
        let rotation = reduceMotion ? 0 : (time * speed).truncatingRemainder(dividingBy: 360)
        let pulse = reduceMotion ? 1 : 0.86 + 0.14 * sin(time * pulseSpeed)
        let gradient = AngularGradient(gradient: Gradient(colors: ListeningActivityPalette.rainbow),
                                       center: .center,
                                       angle: .degrees(rotation))
        let corner: CGFloat = 54
        return ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(gradient, lineWidth: 46)
                .blur(radius: 22)
                .opacity(0.72 * intensity * pulse)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(gradient, lineWidth: 9)
                .blur(radius: 5)
                .opacity(0.80 * intensity * pulse)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(gradient, lineWidth: 3)
                .opacity(0.95 * intensity)
        }
        .padding(1)
        .compositingGroup()
    }

    private var intensity: Double {
        switch phase {
        case .hidden:
            return 0
        case .listening:
            return 1
        }
    }

    private var speed: Double {
        switch phase {
        case .hidden:
            return 0
        case .listening:
            return 80
        }
    }

    private var pulseSpeed: Double {
        switch phase {
        case .hidden:
            return 0
        case .listening:
            return 3.2
        }
    }
}
