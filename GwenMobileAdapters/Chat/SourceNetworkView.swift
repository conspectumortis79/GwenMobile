@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

struct SourceNetworkView: View {
    let review: SourceReview
    let sources: [WebSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionHeadLine(text: L.t("source_network_head"))
            ForEach(Array(review.sourceGroups.enumerated()), id: \.offset) { _, group in
                row(group)
            }
        }
    }

    private func row(_ group: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: group.count > 1 ? "doc.on.doc" : "doc")
                    .scaledFont(11)
                    .foregroundStyle(group.count > 1 ? Color.orange : Color(.tertiaryLabel))
                Text(verbatim: name(group.first ?? 0))
                    .scaledFont(11, weight: .semibold)
                    .lineLimit(1)
            }
            if group.count > 1 {
                Text(verbatim: L.fmt("source_copies_of", copies(group)))
                    .scaledFont(10.5)
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.leading, 16)
            }
        }
    }

    private func copies(_ group: [Int]) -> String {
        group.dropFirst().map { String($0 + 1) }.joined(separator: ", ")
    }

    private func name(_ index: Int) -> String {
        guard index >= 0, index < sources.count else { return "?" }
        return "\(index + 1) · \(sources[index].domain)"
    }
}
