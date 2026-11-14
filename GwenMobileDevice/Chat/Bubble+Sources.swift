import GwenMobileKit
import SwiftUI
import UIKit

extension Bubble {
    func openSource(_ s: WebSource) {
        flowMark("CHIPPROBE action domain=\(s.domain)")
        openWebAddress(s.url)
    }

    func openWebAddress(_ address: String) {
        guard let url = URL(string: address), UIApplication.shared.canOpenURL(url) else {
            flowMark("CHIPPROBE refused url=\(address)")
            return
        }
        flowMark("CHIPPROBE open url=\(address)")
        UIApplication.shared.open(url) { done in flowMark("CHIPPROBE opened=\(done)") }
    }

    func placesView(_ group: PlaceGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(L.t(group.headingKey))
            ForEach(group.places, id: \.self) { place in
                CapsuleAction(horizontal: 9, vertical: 6, action: { onRoute?(place) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .scaledFont(15)
                            .foregroundStyle(Color(.systemGreen))
                        Text(verbatim: place.name)
                            .scaledFont(12, weight: .semibold)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(verbatim: [place.distanceText, place.mode.label].compactMap { $0 }.joined(separator: " · "))
                            .scaledFont(11)
                            .foregroundStyle(Color(.secondaryLabel))
                        Image(systemName: "arrow.turn.up.right")
                            .scaledFont(11, weight: .bold)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
            }
        }
    }

    var sourceReportOnlyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(L.t(sourcesHeadingKey ?? "web_sources_head"))
            if let sourceReport, !sourceReport.isEmpty {
                sourceReportNotice(sourceReport)
            }
        }
    }

    var sourcesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(L.t(sourcesHeadingKey ?? "web_sources_head"))
            OverflowChipRow(spacing: SourceChip.rowSpacing) {
                ForEach(Array(sources.enumerated()), id: \.offset) { idx, s in
                    let flagged = isFlagged(s)
                    CapsuleAction(insets: SourceChip.insets, action: { openSource(s) }) {
                        SourceChipLabel(number: idx + 1, domain: s.domain, flagged: flagged)
                    }
                    .help(s.domain)
                    .contextMenu {
                        Button(action: TapProbe.action({ openSource(s) })) {
                            Label(s.domain, systemImage: "safari")
                        }
                        if SourceReports.shared.isReported(s.domain) {
                            Button(action: TapProbe.action({ withdrawSource(s) })) {
                                Label(L.t("source_report_undo"), systemImage: "arrow.uturn.backward")
                            }
                        } else {
                            Button(role: .destructive, action: TapProbe.action({ reportSource(s) })) {
                                Label(L.t("source_report"), systemImage: "exclamationmark.triangle")
                            }
                        }
                    }
                    .accessibilityLabel(sourceAccessibilityLabel(idx + 1, s, flagged: flagged))
                }
            }
            if let sourceReport, !sourceReport.isEmpty {
                sourceReportNotice(sourceReport)
            }
            if let sourceReview {
                SourceReviewLine(review: sourceReview)
                if sourceReview.copyCount > 0 {
                    SourceNetworkView(review: sourceReview, sources: sources)
                }
                if !sourceReview.warnings.isEmpty {
                    SourceClaimListView(review: sourceReview)
                }
            } else if reviewPending {
                ProcessingLabel(text: L.t("web_check_sources"), size: 11)
            }
        }
    }

    @ViewBuilder
    private func sourceReportNotice(_ report: WebSourceReport) -> some View {
        Button(action: TapProbe.action({ onOpenSourceReport?(report) })) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: report.blockedCount > 0 ? "exclamationmark.shield.fill" : "info.circle.fill")
                    .scaledFont(12)
                    .foregroundStyle(Color(.systemOrange))
                    .frame(width: 17, height: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: sourceReportTitle(report))
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(Color(.label))
                    Text(verbatim: sourceReportDetail(report))
                        .scaledFont(10)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .scaledFont(10, weight: .semibold)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemOrange).opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(.systemOrange).opacity(0.24), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sourceReportTitle(report) + ", " + sourceReportDetail(report))
    }

    private func sourceReportTitle(_ report: WebSourceReport) -> String {
        if !report.sourceIssues.isEmpty {
            if report.blockedCount == report.sourceIssues.count {
                return L.counted(report.sourceIssues.count,
                                 one: "source_report_notice_blocked_one",
                                 many: "source_report_notice_blocked_many")
            }
            return L.counted(report.sourceIssues.count,
                             one: "source_report_notice_unused_one",
                             many: "source_report_notice_unused_many")
        }
        return L.counted(report.searchIssues.count,
                         one: "source_report_notice_search_one",
                         many: "source_report_notice_search_many")
    }

    private func sourceReportDetail(_ report: WebSourceReport) -> String {
        var text = L.fmt2("source_report_used", String(report.used), String(report.requested))
        if let first = report.sourceIssues.first {
            text += " · " + first.domain
        } else if !report.searchIssues.isEmpty {
            text += " · " + L.counted(report.searchIssues.count,
                                      one: "source_report_notice_search_one",
                                      many: "source_report_notice_search_many")
        }
        return text
    }

    func isFlagged(_ source: WebSource) -> Bool {
        let reported = SourceReports.shared.isReported(source.domain)
        return reported || SourceGuard.assess(URL(string: source.url), reported: reported).risk != .clear
    }

    func sourceAccessibilityLabel(_ number: Int, _ source: WebSource, flagged: Bool) -> String {
        let base = L.fmt2("source_chip_label", String(number), source.domain)
        return flagged ? base + ", " + L.t("source_chip_flagged") : base
    }

    func reportSource(_ source: WebSource) {
        SourceReports.shared.report(source.domain)
        notice.show(L.t("source_reported_notice"))
        flowMark("QUELLE gemeldet domain=\(source.domain)")
    }

    func withdrawSource(_ source: WebSource) {
        SourceReports.shared.withdraw(source.domain)
        notice.show(L.t("source_report_removed"))
        flowMark("QUELLE meldung_zurueck domain=\(source.domain)")
    }

    var memoryRefsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(L.t("memory_chip_head"))
            OverflowChipRow(spacing: 6) {
                ForEach(Array(memoryRefs.enumerated()), id: \.offset) { _, ref in
                    RefChip(symbol: ref.category.symbol, colour: MemoryStyle.tint(ref.category),
                            text: TextLine.oneLine(ref.text, limit: 30))
                }
            }
        }
    }

}
