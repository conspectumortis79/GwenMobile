@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import SwiftUI

private let overflowChipRowSpace = "overflowChipRow"

struct ChipRowFades: Equatable, Sendable {
    static let tolerance: CGFloat = 1

    var leading = false
    var trailing = false

    static func of(contentWidth: CGFloat, visible: CGRect?) -> ChipRowFades {
        guard let visible, visible.width > 0 else { return ChipRowFades() }
        return ChipRowFades(leading: visible.minX > tolerance,
                            trailing: visible.maxX < contentWidth - tolerance)
    }
}

struct ChipRowFadeMask: View {
    static let width: CGFloat = 34

    let fades: ChipRowFades

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: fades.leading ? Self.width : 0)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: fades.trailing ? Self.width : 0)
        }
    }
}

struct OverflowChipRow<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content
    @State private var fades = ChipRowFades()

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) {
                row.onGeometryChange(for: ChipRowFades.self) { proxy in
                    ChipRowFades.of(contentWidth: proxy.size.width,
                                    visible: proxy.bounds(of: .named(overflowChipRowSpace)))
                } action: { fades = $0 }
            }
            .coordinateSpace(.named(overflowChipRowSpace))
            .mask { ChipRowFadeMask(fades: fades) }
        }
    }

    private var row: some View {
        HStack(spacing: spacing) { content }
    }
}
