@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

struct SourceClaimListView: View {
    let review: SourceReview

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionHeadLine(text: L.t("source_report_head"))
            ForEach(Array(review.warnings.enumerated()), id: \.offset) { _, result in
                row(result)
            }
        }
    }

    private func row(_ result: SourceReview.ClaimResult) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: symbol(result.verdict))
                .scaledFont(11)
                .foregroundStyle(color(result.verdict))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: result.claim)
                    .scaledFont(11)
                    .foregroundStyle(Color(.label))
                    .lineLimit(2)
                if let detail = Self.detail(result) {
                    Text(verbatim: detail)
                        .scaledFont(10.5)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                }
            }
        }
    }

    nonisolated static func detail(_ result: SourceReview.ClaimResult) -> String? {
        var parts: [String] = []
        if !result.sources.isEmpty {
            parts.append(L.fmt("source_claim_sources", result.sources.map { "[\($0)]" }.joined()))
        }
        if !result.contradicts.isEmpty {
            parts.append(L.fmt("source_claim_contradicts", result.contradicts.map { "[\($0)]" }.joined()))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func symbol(_ verdict: ClaimVerdict) -> String {
        switch verdict {
        case .supported: return "checkmark.circle.fill"
        case .unsupported, .unknown: return "questionmark.circle.fill"
        case .contradicted: return "exclamationmark.octagon.fill"
        }
    }

    private func color(_ verdict: ClaimVerdict) -> Color {
        switch verdict {
        case .supported: return .green
        case .unsupported, .unknown: return .orange
        case .contradicted: return .red
        }
    }
}
