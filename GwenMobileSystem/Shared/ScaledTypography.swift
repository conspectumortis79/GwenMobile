@testable import GwenMobileFeatureCore
import SwiftUI

struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    nonisolated init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle?) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style ?? ScaledFontModifier.style(for: size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }

    nonisolated static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<10: return .caption2
        case ..<12: return .caption
        case ..<15: return .footnote
        case ..<17: return .subheadline
        case ..<20: return .body
        case ..<24: return .title3
        default: return .title2
        }
    }
}

extension View {
    nonisolated func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular,
                                design: Font.Design = .default,
                                relativeTo style: Font.TextStyle? = nil) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design, relativeTo: style))
    }
}
