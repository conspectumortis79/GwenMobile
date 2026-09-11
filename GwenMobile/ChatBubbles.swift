import SwiftUI

struct WebStatusBubble: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .tint(.blue)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Capsule().fill(Color(.systemGray5)))
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

struct TypingDots: View {
    var body: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.mini)
                .tint(Color(.systemGray))
        }
    }
}
