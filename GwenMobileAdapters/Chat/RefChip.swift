@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

struct RefChip: View {
    let symbol: String
    let colour: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .scaledFont(11)
                .foregroundStyle(colour)
            Text(verbatim: text)
                .scaledFont(12, weight: .semibold)
                .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(Color(.systemGray5)))
    }
}
