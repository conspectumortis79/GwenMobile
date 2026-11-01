@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

struct WebStatusBubble: View {
    let text: String
    var body: some View {
        ProcessingLabel(text: text, size: 13.5, lineLimit: 1)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(Color(.systemGray5)))
    }
}

struct SectionHeadLine: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .scaledFont(11, weight: .semibold)
            .foregroundStyle(Color(.secondaryLabel))
    }
}

struct BubbleShape: Shape {
    let isUser: Bool
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: 20, bottomLeadingRadius: isUser ? 20 : 6,
            bottomTrailingRadius: isUser ? 6 : 20, topTrailingRadius: 20,
            style: .continuous
        ).path(in: rect)
    }
}

struct StatusBubble: View {
    let text: String
    var body: some View {
        ProcessingLabel(text: text)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color(.systemGray5))
            .clipShape(BubbleShape(isUser: false))
    }
}
