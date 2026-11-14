import Foundation
import SwiftUI

struct ProviderConsoleBalanceCard: View {
    let descriptor: any ProviderDescriptor
    let consoleURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProviderHeaderRow(glyph: descriptor.glyph, title: descriptor.title,
                              caption: L.t("balance_console_caption")) {
                statusPill
            }
            Text(L.t("balance_console_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)
            Link(destination: consoleURL) {
                HStack(spacing: 6) {
                    Text(L.t("balance_console_action"))
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.top, 11)
                .padding(.bottom, 2)
            }
        }
        .padding(16)
        .background(ProviderCardBackground(glyph: descriptor.glyph))
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(.systemGray))
                .frame(width: 6, height: 6)
            Text(L.t("balance_console_status"))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color(.systemGray).opacity(0.12), in: Capsule())
        .foregroundStyle(Color(.systemGray))
        .fixedSize()
    }
}
