@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

@MainActor
struct PriceWatchCardView: View {
    let ref: PriceWatchRef

    private var tint: Color { ref.status.tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeadLine(text: L.t("price_watch_card_head"))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: "tag.fill")
                        .scaledFont(15)
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: ref.product)
                            .scaledFont(13, weight: .semibold)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(verbatim: L.fmt("price_watch_list_goal", ref.goalText))
                                .scaledFont(11)
                                .foregroundStyle(Color(.secondaryLabel))
                            Text(verbatim: ref.statusText)
                                .scaledFont(11, weight: .semibold)
                                .foregroundStyle(tint)
                        }
                    }
                    Spacer(minLength: 8)
                    if let best = ref.bestText {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(verbatim: best)
                                .scaledFont(12, weight: .semibold)
                                .multilineTextAlignment(.trailing)
                            if let product = ref.bestProduct, !product.isEmpty,
                               PriceWatch.fold(product) != PriceWatch.fold(ref.product) {
                                Text(verbatim: product)
                                    .scaledFont(10)
                                    .foregroundStyle(Color(.secondaryLabel))
                                    .multilineTextAlignment(.trailing)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    if let stamp = ref.chipStamp {
                        Text(verbatim: stamp)
                            .scaledFont(11)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    Spacer(minLength: 6)
                    if ref.isOpenable {
                        Button(action: TapProbe.action({
                            openOffer()
                        })) {
                            Label(L.t("price_watch_open_offer"), systemImage: "arrow.up.forward.app")
                                .scaledFont(12, weight: .semibold)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(tint)
                        .accessibilityLabel(L.t("price_watch_open_offer"))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 288, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1))
        }
    }

    private func openOffer() {
        guard let bestURL = ref.bestURL, let url = URL(string: bestURL) else { return }
        UIApplication.shared.open(url) { opened in
            flowMarkPersonal("PREISWECKER angebot geoeffnet=\(opened) domain=\(url.host ?? "-")")
        }
    }
}

extension PriceWatch.Status {
    var tint: Color {
        switch self {
        case .hit: return Color(.systemGreen)
        case .paused: return Color(.secondaryLabel)
        case .waiting: return Color(.systemOrange)
        }
    }
}
