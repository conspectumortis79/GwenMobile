@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

struct SourceReviewLine: View {
    let review: SourceReview

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let line = verificationLine {
                label(line.symbol, line.text, line.color)
            }
            if let line = independenceLine {
                label(line.symbol, line.text, line.color)
            }
        }
    }

    private var verificationLine: (symbol: String, text: String, color: Color)? {
        guard review.verified else {
            guard review.verificationMissing else { return nil }
            return ("exclamationmark.triangle.fill", L.t("source_check_unverified"), .orange)
        }
        if !review.contradicted.isEmpty {
            let text = L.counted(review.contradicted.count, one: "source_contradicted_one",
                                 many: "source_contradicted_many")
            return ("exclamationmark.octagon.fill", text, .red)
        }
        guard !review.unsupported.isEmpty else {
            return ("checkmark.seal.fill", L.t("source_verified"), .green)
        }
        let text = L.counted(review.unsupported.count, one: "source_unsupported_one",
                             many: "source_unsupported_many")
        return ("exclamationmark.triangle.fill", text, .orange)
    }

    private var independenceLine: (symbol: String, text: String, color: Color)? {
        if review.citedDuplicates > 0 {
            return ("exclamationmark.triangle.fill",
                    L.fmt2("source_duplicates", String(review.citedOrigins), String(review.citedSources)),
                    .orange)
        }
        if review.singleSource {
            return ("exclamationmark.circle", L.t("source_single"), .orange)
        }
        if review.crossChecked {
            return ("checkmark.circle", L.t("source_multiple"), Color(.secondaryLabel))
        }
        guard review.citedClaims == 0, review.sourceDomains > 0 else { return nil }
        return ("questionmark.circle", L.t("source_uncited"), .orange)
    }

    private func label(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .scaledFont(11)
                .foregroundStyle(color)
            Text(verbatim: text)
                .scaledFont(11)
                .foregroundStyle(Color(.secondaryLabel))
        }
    }
}
