@testable import GwenMobileFeatureCore
import SwiftUI

struct CardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(width: 300)
            .background(RoundedRectangle(cornerRadius: 15).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color(.separator).opacity(0.45), lineWidth: 0.5))
    }
}

extension View {
    func cardChrome() -> some View { modifier(CardChrome()) }
}
