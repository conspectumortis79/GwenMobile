@testable import GwenMobileFeatureCore
import GwenMobileKit
import SwiftUI

struct DayTabPicker: View {
    struct Tab: Identifiable {
        let id: String
        let title: String
    }

    let tabs: [Tab]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button(action: TapProbe.action({
                    onSelect(tab.id)
                })) {
                    Text(verbatim: tab.title)
                        .scaledFont(12.5, weight: .semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(tab.id == selected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(tab.id == selected ? Color(.systemBackground) : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(.tertiarySystemFill)))
    }
}
